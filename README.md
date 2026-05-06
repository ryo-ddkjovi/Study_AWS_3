# WordPress on AWS - ECS Fargate 構成3

構成2のEC2 WordPress部分をECS Fargateに置き換えた構成です。

- CloudFront -> ALB -> ECS Fargate x 2 -> RDS MySQL
- WordPressファイルはEFSに永続化
- DB情報はSecrets ManagerからECSタスクに渡す
- DockerイメージはECRにpush
