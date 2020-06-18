data "aws_route53_zone" "zone" {
    count               = "${var.hosted_zone_name != "" ? 1 : 0}"
    name                = var.hosted_zone_name
    private_zone        = var.private_hosted_zone
}

resource "aws_route53_record" "route53_record" {
    count   = var.hosted_zone_name != "" ? 1 : 0
    zone_id = data.aws_route53_zone.zone[0].zone_id
    name    = "${var.hosted_zone_record_prefix}.${data.aws_route53_zone.zone[0].name}"
    type    = "A"
    alias {
        name                   = aws_lb.opscenter.dns_name
        zone_id                = aws_lb.opscenter.zone_id
        evaluate_target_health = false
    }
}