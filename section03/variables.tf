variable "vpc_cidr" {
    type    = string
    default = "172.16.0.0/16"
}
variable "subnet_cidrs" {
    type = map(list(string))

    default = {        
        app    : ["172.16.0.0/24", "172.16.1.0/24", "172.16.2.0/24", "172.16.3.0/24"],
        db     : ["172.16.100.0/24", "172.16.101.0/24"],
        public : ["172.16.200.0/24", "172.16.201.0/24"]
    }
}