resource "aws_instance" "main" {
  ami                  = local.ami_id
  instance_type        = "t3.micro" # Cost-effective instance type
  subnet_id            = local.private_subnet_id
  vpc_security_group_ids = [local.sg_id]

  tags = merge(
    local.common_tags,
    {
        Name = "${local.common_name}"
    }
  )
}

resource "terraform_data" "main" {
  triggers_replace = [
    aws_instance.main.id
  ]


connection {
      type        = "ssh"
      user        = "ec2-user"
      password    = "DevOps321"
      host        = aws_instance.main.private_ip
    }

    provisioner "file" {
    source      = "bootstrap.sh"
    destination = "/tmp/bootstrap.sh"
  }


    provisioner "remote-exec" {
     inline = [
      "chmod +x /tmp/bootstrap.sh",
      "sudo sh /tmp/bootstrap.sh ${var.component} ${var.environment} ${var.app_version}"
    ]
  }
}

resource "aws_ec2_instance_state" "main" {
  instance_id = aws_instance.main.id
  state       = "stopped" # Switch to "running" to start it back up
  depends_on = [terraform_data.main]
}

resource "aws_ami_from_instance" "main" {
  name               ="${local.common_name}-${var.app_version}-${aws_instance.main.id}"
  source_instance_id = aws_instance.main.id 
  depends_on = [aws_ec2_instance_state.main]

  tags = merge(
    local.common_tags,
    {
        Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
    }
  )
}

resource "aws_launch_template" "main" {
  name = "${local.common_name}"
  image_id = "aws_ami_from_instance.main.id"

  instance_initiated_shutdown_behavior = "terminate"

  instance_type = "t3.micro"

  vpc_security_group_ids = [local.sg_id]

  tag_specifications {
    resource_type = "instance"

    tags = merge(
        local.common_tags,
        {
            Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
        }
    ) 
  }

  tag_specifications {
    resource_type = "volume"

    tags = merge(
        local.common_tags,
        {
            Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
        }
    ) 
  }

  

    tags = merge(
        local.common_tags,
        {
            Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
        }
    ) 
  
}


# Create the Target Group
resource "aws_lb_target_group" "main" {
  name        = "${local.common_name}"
  port        = var.component == "frontend" ? "80" : "8080"
  protocol    = "HTTP"
  vpc_id      = "local.vpc_id" # Replace with your VPC ID
  target_type = "instance"               # Options: instance, ip, lambda, alb
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                =  var.component == "frontend" ? "/" : "/health"
    port                = var.component == "frontend" ? "80" : "8080"
    protocol            = "HTTP"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200" # Expected HTTP response code
  }

  # Best practice: avoids downtime during replacements
  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
        local.common_tags,
        {
            Name = "${local.common_name}-${var.app_version}-${aws_instance.main.id}"
        }
    ) 
  
}

resource "aws_autoscaling_group" "main" {
  name_prefix         = "${local.common_name}"
  vpc_zone_identifier = [local.private_subnet_id] # Replace with your private subnets
  target_group_arn = [aws_lb_target_group.main.arn]

  min_size         = 1
  max_size         = 10
  desired_capacity = 2
  health_check_type   = "EC2"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  # Best practice: Ignore capacity changes if you use dynamic scaling policies
  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }

   instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
    triggers = ["launch_template"]
  }
   
   dynamic "tag" {
    for_each = merge(
       local.common_tags,
     {
        Name = "${local.common_name}"
     }
    )
    content {
     key                 = "tag.key"
     value               = "tag.value"
     propagate_at_launch = true
    }
   
     timeouts {
        delete = "15m"
     }
   }  
}

resource "aws_autoscaling_policy" "main" {
  name                   = "${local.common_name}"
  autoscaling_group_name = aws_autoscaling_group.main.name 
  policy_type            = "TargetTrackingScaling"  
  estimated_instance_warmup = 120 

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 75.0 # Target 75% CPU utilization
  }
}

resource "aws_lb_listener_rule" "main" {
  listener_arn = local.alb_listener_arn
  priority     = var.rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  condition {
    host_header {
      values = [local.host_header]
    }
  }
}

resource "terraform_data" "main_delete" {
  triggers_replace = [
    aws_instance.main.id
  ]
  depends_on = [aws_autoscaling_policy.main]

  # executes where terraform is running
  provisioner "local-exec" {
    command = "aws ec2 terminate-instances --instance-ids ${aws_instance.main.id}"
  }
}
