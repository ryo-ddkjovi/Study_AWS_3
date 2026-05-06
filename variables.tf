variable "aws_region" {
  description = "AWSリージョン"
  type        = string
  default     = "ap-northeast-1"
}

variable "db_user" {
  description = "RDS MySQLのユーザー名"
  type        = string
}

variable "db_pass" {
  description = "RDS MySQLのパスワード"
  type        = string
  sensitive   = true
}

variable "my_ip" {
  description = "踏み台サーバへのSSHを許可する自分のグローバルIP。例: 153.xxx.xxx.xxx/32"
  type        = string
}

variable "restore_db_endpoint" {
  description = "復元DBに切り替えるときのエンドポイント。通常は空。"
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "ECRにpushするWordPressイメージのタグ"
  type        = string
  default     = "latest"
}

variable "bastion_ami_id" {
  description = "踏み台サーバ用Ubuntu AMI ID。構成2と同じAMIを初期値にしています。"
  type        = string
  default     = "ami-0d52744d6551d851e"
}
