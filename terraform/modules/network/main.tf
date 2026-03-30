
resource "aws_vpc" "example" {
  cidr_block = var.vpc_cidr

  tags = {
    Name = "${var.env_name}-vpc"
  }
}


data "aws_availability_zones" "available" {
  state = "available"
}

# インターネットゲートウェイ (IGW)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.example.id
}

resource "aws_subnet" "public" {

  count = length(var.public_subnet_cidrs)

  vpc_id = aws_vpc.example.id

  cidr_block = var.public_subnet_cidrs[count.index]

  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true # 自動的にパブリックIPを割り当てる

  tags = {
    Name = "${var.env_name}-public-subnet-${count.index + 1}"
  }
}

# ルートテーブル
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {

  count = length(var.public_subnet_cidrs)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}



# プライベートサブネットの作成 
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.example.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  # パブリックIPは付与しない
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.env_name}-private-subnet-${count.index + 1}"
  }
}

# プライベートサブネット用のルートテーブル
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "${var.env_name}-private-rt"
  }
}

# プライベートサブネットとルートテーブルの関連付け
resource "aws_route_table_association" "private" {
  count          = length(var.private_subnet_cidrs)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}



#   NAT Gateway用のElastic IP
resource "aws_eip" "nat" {
  domain = "vpc" # vpc = true
  tags   = { Name = "${var.env_name}-nat-eip" }
}

#  NAT Gateway本体 
resource "aws_nat_gateway" "example" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = { Name = "${var.env_name}-nat-gw" }
}

resource "aws_route" "private_nat" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.example.id
}
