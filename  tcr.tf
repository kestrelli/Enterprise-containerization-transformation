resource "tencentcloud_tcr_instance" "tcr" {
  name          = "tcr-kestrelli-${random_string.suffix.result}"
  instance_type = "basic"
  tags = {
    billing = "kestrelli"
    env     = "prod"
  }
}

resource "tencentcloud_tcr_namespace" "default" {
  instance_id    = tencentcloud_tcr_instance.tcr.id
  name           = "default"
  is_public      = true
}

resource "tencentcloud_tcr_repository" "petclinic" {
  instance_id    = tencentcloud_tcr_instance.tcr.id
  namespace_name = tencentcloud_tcr_namespace.default.name
  name           = "petclinic"
  brief_desc     = "Spring PetClinic application"
}

resource "tencentcloud_tcr_token" "ci_token" {
  instance_id  = tencentcloud_tcr_instance.tcr.id
  description  = "CI/CD access token"
  enable       = true
}