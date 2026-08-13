# Tenancy-wide spend alert (created in the console, imported into terraform).
# Everything in this stack should stay inside Always Free allowances, so the
# 50%-of-$5 alert firing means something unexpected is billing.
resource "oci_budget_budget" "tenancy" {
  compartment_id = var.tenancy_ocid
  display_name   = "50-percept-of-5-buck-month"
  description    = "reached 50% of $5 monthly budget"
  amount         = 5
  reset_period   = "MONTHLY"
  target_type    = "COMPARTMENT"
  targets        = [var.tenancy_ocid]
}

resource "oci_budget_alert_rule" "half_spent" {
  budget_id      = oci_budget_budget.tenancy.id
  display_name   = "alertrule20260813034313"
  type           = "ACTUAL"
  threshold      = 50
  threshold_type = "PERCENTAGE"
  recipients     = "cody@codywilliams.dev"
  message        = "CHECK OCI SPENDING ASAP"
}
