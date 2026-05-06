output "ecr_repository_url" {
  description = "DockerイメージをpushするECRリポジトリURL"
  value       = aws_ecr_repository.wordpress.repository_url
}

output "ecs_cluster_name" {
  description = "ECSクラスター名"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "ECSサービス名"
  value       = aws_ecs_service.wordpress.name
}

output "alb_dns" {
  description = "ALBのDNS名"
  value       = aws_lb.alb.dns_name
}

output "alb_url" {
  description = "ALBでアクセスするURL"
  value       = "http://${aws_lb.alb.dns_name}"
}

output "cloudfront_domain" {
  description = "CloudFrontのドメイン"
  value       = aws_cloudfront_distribution.wordpress.domain_name
}

output "cloudfront_url" {
  description = "WordPressのURL（基本はこちらを使う）"
  value       = "https://${aws_cloudfront_distribution.wordpress.domain_name}"
}

output "rds_endpoint" {
  description = "RDSのエンドポイント"
  value       = aws_db_instance.mysql.address
}

output "efs_id" {
  description = "WordPressファイル永続化用EFS ID"
  value       = aws_efs_file_system.wordpress.id
}

output "bastion_public_ip" {
  description = "踏み台サーバのIP"
  value       = aws_instance.bastion.public_ip
}

output "bastion_ssh_command" {
  description = "SSH接続コマンド"
  value       = "ssh -i bastion-key.pem ubuntu@${aws_instance.bastion.public_ip}"
}

output "rds_mysql_command" {
  description = "踏み台サーバからRDSに接続するコマンド"
  value       = "mysql -h ${aws_db_instance.mysql.address} -u ${var.db_user} -p"
}
