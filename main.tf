terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region     = "us-east-1"
  access_key = ""
  secret_key = ""
}



# # 1. Creating a VPC so that resources can be deployed in them.

resource "aws_vpc" "http-vpc" {
 cidr_block = "192.168.0.0/24"
 tags = {
     Name = "httpvpc"
    }
}

# # 2. Create Internet Gateway

resource "aws_internet_gateway" "igw" {
 vpc_id = aws_vpc.http-vpc.id

}

# # 3. Create Custom Route Table

resource "aws_route_table" "http-route-table" {
 vpc_id = aws_vpc.http-vpc.id

    route {
     cidr_block = "0.0.0.0/0"
     gateway_id = aws_internet_gateway.igw.id
    }

   route {
     ipv6_cidr_block = "::/0"
     gateway_id      = aws_internet_gateway.igw.id
   }

   tags = {
     Name = "http"
   }
}

# # 4. Create a Subnet 

resource "aws_subnet" "http-subnet" {
 vpc_id            = aws_vpc.http-vpc.id
 cidr_block        = "192.168.0.0/24"
 availability_zone = "us-east-1a"

   tags = {
     Name = "http-subnet"
   }
}

# # 5. Associate subnet with Route Table

 resource "aws_route_table_association" "snrt" {
   subnet_id      = aws_subnet.http-subnet.id
   route_table_id = aws_route_table.http-route-table.id
}



# # 6. Create Security Group to allow port 22,80,443

 resource "aws_security_group" "allow_web" {
   name        = "allow_web_traffic"
   description = "Allow Web inbound traffic"
   vpc_id      = aws_vpc.http-vpc.id

   ingress {
     description = "HTTPS"
     from_port   = 443
     to_port     = 443
     protocol    = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
   }
   ingress {
     description = "HTTP"
     from_port   = 80
     to_port     = 80
     protocol    = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
   }
   ingress {
     description = "SSH"
     from_port   = 22
     to_port     = 22
     protocol    = "tcp"
     cidr_blocks = ["0.0.0.0/0"]
   }

   egress {
     from_port   = 0
     to_port     = 0
     protocol    = "-1"
     cidr_blocks = ["0.0.0.0/0"]
   }

   tags = {
     Name = "allow_web"
   }
}

#DB security group
#resource "aws_security_group" "db-sg" {
#name          = "db-sg"
#vpc_id        = aws_vpc.http-vpc.id
#description   = "Allow TLS inbound traffic"
#ingress {
#description = "SSH"
#from_port   = 22
#to_port     = 22
#protocol    = "tcp"
#cidr_blocks = ["0.0.0.0/0"]
#}
#ingress {
#description = "MYSQL"
#from_port   = 3306
#to_port     = 3306
#protocol    = "tcp"
#cidr_blocks = [aws_subnet.http-subnet.cidr_block]
#}
#egress {
#from_port   = 0
#to_port     = 0
#protocol    = "-1"
#cidr_blocks = ["0.0.0.0/0"]
#}
#tags = {
#Name = "http-subnet"
#}
#}


# # 7. Create a network interface with an ip address in the subnet that was created abouve in step number 4 

 resource "aws_network_interface" "http-server-nic" {
   subnet_id       = aws_subnet.http-subnet.id
   private_ips     = ["192.168.0.12"]
   security_groups = [aws_security_group.allow_web.id]
}


# # 8. Assign an elastic IP to the network interface created in step 7

 resource "aws_eip" "one" {
   vpc                       = true
   network_interface         = aws_network_interface.http-server-nic.id
   associate_with_private_ip = "192.168.0.12"
   depends_on                = [aws_internet_gateway.igw]
}

# output "server_public_ip" {
#   value = aws_eip.one.public_ip
# }

# # 9. Create Ubuntu http web server and install/enable apache2

resource "aws_instance" "http-server-instance" {
   ami               = "ami-00ddb0e5626798373"
   instance_type     = "t2.micro"
   availability_zone = "us-east-1a"
   key_name          = "http-key"

  root_block_device {
   volume_type = "gp2"
   volume_size = "10"
 }

   network_interface {
     device_index         = 0
     network_interface_id = aws_network_interface.http-server-nic.id
   }

   user_data = <<-EOF
                 #! /bin/bash
                sudo apt-get update
		        sudo apt-get install -y apache2
		        sudo systemctl start apache2
		        sudo systemctl enable apache2
		        echo "<h1>Deployed via Terraform</h1>" | sudo tee /var/www/html/index.html
	EOF 
   tags = {
     Name = "http-server"
   }
 }



 output "server_private_ip" {
   value = aws_instance.http-server-instance.private_ip

 }

 output "server_id" {
   value = aws_instance.http-server-instance.id
}





##database server

# Create a network interface with an ip in the subnet that was created in step 4

 resource "aws_network_interface" "db-instance-nic" {
   subnet_id       = aws_subnet.http-subnet.id
   private_ips     = ["192.168.0.24"]
   security_groups = [aws_security_group.allow_web.id]

}
# # 8. Assign an elastic IP to the network interface created in step 7

 resource "aws_eip" "db" {
   vpc                       = true
   network_interface         = aws_network_interface.db-instance-nic.id
   associate_with_private_ip = "192.168.0.24"
   depends_on                = [aws_internet_gateway.igw]
}

 output "server_public_ip" {
   value = aws_eip.db.public_ip
}

# # 9. Create Ubuntu server and install/enable apache2

resource "aws_instance" "db-instance" {
   ami               = "ami-00ddb0e5626798373"
   instance_type     = "t2.micro"
   availability_zone = "us-east-1a"
   key_name          = "db-key"
   root_block_device {
    volume_type = "gp2"
    volume_size = "10"   
    }


  ebs_block_device {
   device_name = "/dev/xvdb"
   volume_size = 15
   volume_type = "gp2"
   delete_on_termination = false
   }


   network_interface {
     device_index         = 0
     network_interface_id = aws_network_interface.db-instance-nic.id
    }

   user_data = <<-EOF
                 #!/bin/bash
                 sudo apt update -y
                 sudo apt install mysql mysql-cli -y
                 sudo systemctl enable mysql
                 sudo systemctl start mysql
                 EOF
   tags = {
     Name = "db-instance"
    }
}


 output "serverdb_private_ip" {
   value = aws_instance.db-instance.private_ip

}

 output "serverdb_id" {
   value = aws_instance.db-instance.id
}

