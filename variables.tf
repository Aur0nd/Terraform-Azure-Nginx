variable "location"{
    type = string 
}

variable "zones" {
    type = list(string)
    default = []
}
variable "resource_prefix" {
    type = map(string)
}