module "user_nfs_softnas" {
  source = "./modules/user_nfs_softnas"

  num_instances             = var.softnas_num_instances
  softnas_ami_id            = var.softnas_ami_id
  instance_type             = var.softnas_instance_type
  default_volume_size       = var.softnas_volume_size
  vpc_id                    = data.aws_vpc.main.id
  node_security_group_id    = data.aws_security_group.node.id
  bastion_security_group_id = data.aws_security_group.bastion.id
  subnet_ids                = var.softnas_subnet_ids # This is now hard coded to this subnet as changing it destroys volumes
  ssh_public_key            = var.softnas_ssh_public_key
  dns_zone_id               = data.aws_route53_zone.main.zone_id
  dns_zone_domain           = "${terraform.workspace}.mojanalytics.xyz"
  is_production             = var.is_production

  tags = merge(
    {
      "component" = "SoftNAS"
    },
    var.tags,
  )
}

module "ebs_snapshots" {
  source = "./modules/ebs_snapshots"

  name = "${terraform.workspace}-dlm"

  target_tags = {
    env = terraform.workspace
  }

  tags = var.tags
}

module "softnas_monitoring" {
  source = "./modules/cloudwatch_alerts"

  name = "${terraform.workspace}-softnas-alerts"

  # The logic below has been added as we only want alerts for one SoftNAS instance
  ec2_instance_ids   = [element(module.user_nfs_softnas.ec2_instance_ids, 1)]
  ec2_instance_names = [element(module.user_nfs_softnas.ec2_instance_names, 1)]
  cpu_threshold      = 70
  cpu_low_threshold  = var.softnas_cpu_low_threshold
  email              = "analytics-platform-tech@digital.justice.gov.uk"

  tags = merge(
    {
      "component" = "SoftNAS"
    },
    var.tags,
  )
}

module "concourse_parameter_user" {
  source = "./modules/user_get_parameter"

  user_name = "concourse"
}

module "data_backup" {
  source = "./modules/data_backup"

  k8s_worker_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/nodes.${terraform.workspace}.${var.platform_root_domain}"
  logs_bucket_arn     = var.log_bucket_name
}

module "container_registry" {
  source = "./modules/container_registry"
}

module "control_panel_api" {
  source = "./modules/control_panel_api"

  db_username                = var.control_panel_api_db_username
  db_password                = var.control_panel_api_db_password
  k8s_worker_role_arn        = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/nodes.${terraform.workspace}.${var.platform_root_domain}"
  account_id                 = data.aws_caller_identity.current.account_id
  vpc_id                     = data.aws_vpc.main.id
  db_subnet_ids              = data.aws_subnet_ids.storage.ids
  ingress_security_group_ids = [data.aws_security_group.node.id]
  redis_node_type            = var.control_panel_redis_node_type
  redis_password             = var.control_panel_redis_password
  redis_engine_version       = "5.0.6"

  tags = merge(
    {
      "component" = "Control Panel"
    },
    var.tags,
  )
}

module "airflow_storage_efs_volume" {
  source = "./modules/efs_volume"

  name                   = "${terraform.workspace}-airflow-storage"
  vpc_id                 = data.aws_vpc.main.id
  node_security_group_id = data.aws_security_group.node.id
  subnet_ids             = data.aws_subnet_ids.storage.ids
  num_subnets = length(
    data.aws_subnet_ids.storage.ids,
  )
}

module "airflow_db" {
  source = "./modules/postgres_db"

  instance_name          = "${terraform.workspace}-airflow"
  instance_class         = "db.m3.medium"
  db_name                = "airflow"
  username               = var.airflow_db_username
  password               = var.airflow_db_password
  vpc_id                 = data.aws_vpc.main.id
  node_security_group_id = data.aws_security_group.node.id
  subnet_ids             = data.aws_subnet_ids.storage.ids
}

module "airflow_smtp_user" {
  source = "./modules/ses_smtp_user"

  ses_address_identity_arn = var.ses_ap_email_identity_arn
  iam_user_name            = "${terraform.workspace}_airflow_smtp_user"
}

module "cert_manager" {
  source = "./modules/ec2_cert_manager_role"

  role_name      = "${terraform.workspace}-cert-manager"
  trusted_entity = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/nodes.${terraform.workspace}.${var.platform_root_domain}"]
  hosted_zone_id = data.aws_route53_zone.main.zone_id
}

resource "aws_iam_policy" "read-user-roles-inline-policies" {
  name = "${terraform.workspace}-read-user-roles-inline-policies"
  path = "/"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CanReadUserRolesInlinePolicies",
            "Effect": "Allow",
            "Action": [
                "iam:GetRolePolicy"
            ],
            "Resource": [
                "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${terraform.workspace}_user_*"
            ]
        }
    ]
}
EOF

}

module "cluster_autoscaler" {
  source = "./modules/ec2_cluster_autoscaler_policy"

  policy_name        = "${terraform.workspace}-cluster-autoscaler"
  instance_role_name = ["nodes.${terraform.workspace}.${var.platform_root_domain}"]

  auto_scaling_groups = [
    "nodes.${terraform.workspace}.${var.platform_root_domain}",
    "highmem-nodes.${terraform.workspace}.${var.platform_root_domain}",
  ]
}

module "buckets_archiver" {
  source = "./modules/buckets_archiver"

  name                = "${terraform.workspace}-archived-buckets-data"
  logging_bucket_name = var.log_bucket_name
  expiration_days     = 183 # 6 months
  k8s_worker_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/nodes.${terraform.workspace}.${var.platform_root_domain}"
  region              = var.region

  tags = merge(
    {
      "component" = "buckets-archiver"
    },
    var.tags,
  )
}

module "ap_infra_alert_topic" {
  source = "./modules/sns_alerts"

  name  = "${terraform.workspace}-ap-infra-alerts"
  email = "analytics-platform-tech@digital.justice.gov.uk"
  tags  = var.tags
}

module "kubernetes_master_monitoring" {
  source = "./modules/elb_cloudwatch_alerts"

  name          = "${terraform.workspace}-kubernetes-master-alerts"
  elb_name      = "api-${terraform.workspace}"
  alarm_actions = [module.ap_infra_alert_topic.stack_notifications_arn]

  tags = merge(
    {
      "component" = "Kubernetes"
    },
    var.tags,
  )
}

module "kubernetes_master_asg_monitoring" {
  source = "./modules/asg_cloudwatch_alerts"

  name          = "${terraform.workspace}-kubernetes-master-asg-alerts"
  asg_names     = ["master-${var.region}a.masters.${terraform.workspace}.mojanalytics.xyz", "master-${var.region}b.masters.${terraform.workspace}.mojanalytics.xyz", "master-${var.region}c.masters.${terraform.workspace}.mojanalytics.xyz"]
  alarm_actions = [module.ap_infra_alert_topic.stack_notifications_arn]

  tags = merge(
    {
      "component" = "Kubernetes"
    },
    var.tags,
  )
}

module "kubernetes_node_asg_monitoring" {
  source = "./modules/asg_cloudwatch_alerts"

  name                       = "${terraform.workspace}-kubernetes-node-asg-alerts"
  asg_names                  = ["nodes.${terraform.workspace}.mojanalytics.xyz"]
  alarm_actions              = [module.ap_infra_alert_topic.stack_notifications_arn]
  desired_capacity_threshold = var.k8s_desired_capacity_threshold
  cpu_threshold              = 90

  tags = merge(
    {
      "component" = "Kubernetes"
    },
    var.tags,
  )
}

module "bastion" {
  source                       = "Guimove/bastion/aws"
  version                      = "2.2.2"
  region                       = var.region
  vpc_id                       = var.vpc_id
  bastion_ami                  = data.aws_ami.ubuntu.id
  is_lb_private                = false
  bastion_host_key_pair        = var.bastion_host_key_pair
  create_dns_record            = true
  hosted_zone_id               = data.aws_route53_zone.main.zone_id
  bastion_record_name          = "bastion.${terraform.workspace}.mojanalytics.xyz"
  bucket_name                  = "analytical-platform-${terraform.workspace}-bastion-logs"
  bastion_launch_template_name = "${terraform.workspace}-bastion"
  bastion_iam_policy_name      = "${terraform.workspace}-bastion"
  bastion_additional_security_groups = [
    data.aws_security_group.bastion.id,
    data.aws_security_group.bastion-main.id
  ]
  elb_subnets                = var.dmz_subnet_ids
  auto_scaling_group_subnets = var.dmz_subnet_ids
  tags = merge(
    {
      "component" = "Bastion"
    },
    var.tags,
  )
}

resource "aws_cloudwatch_metric_alarm" "bastion_healthy_hosts" {
  alarm_name        = "${terraform.workspace}-bastion-healthy-hosts-alarm"
  alarm_description = "This metric monitors the number of Healthy hosts in an NLB"

  dimensions = {
    LoadBalancer = data.aws_lb.bastion.arn_suffix
    TargetGroup  = data.aws_lb_target_group.bastion.arn_suffix
  }

  namespace           = "AWS/NetworkELB"
  metric_name         = "HealthyHostCount"
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  treat_missing_data  = "breaching"

  actions_enabled = "true"
  alarm_actions   = [module.ap_infra_alert_topic.stack_notifications_arn]

  tags = merge(
    {
      "component" = "Bastion"
    },
    var.tags,
  )
}
