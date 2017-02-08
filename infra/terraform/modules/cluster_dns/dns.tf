resource "aws_route53_zone" "env" {
   # name = "${var.env}.${data.terraform_remote_state.base.xyz_dns_zone_name}"
   name = "${var.env}.${var.root_zone_name}"
   force_destroy = "false"
}

resource "aws_route53_record" "root_ns_record" {
   # zone_id = "${data.terraform_remote_state.base.xyz_dns_zone_id}"
   zone_id = "${var.root_zone_id}"
   name = "${var.env}"
   type = "NS"
   ttl = "300"
   records = ["${aws_route53_zone.env.name_servers}"]
}
