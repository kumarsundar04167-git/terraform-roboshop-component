variable "project" {
    default = "roboshop"
}

variable "environment" {
    default = "dev"
}

variable "app_version" {
    default = "v3"
}

variable "component" {
    type = string
}

variable "domain_name" {
    default = "devopsonline.online"
    type = string
}

variable "rule_priority" {
    #type = string
}