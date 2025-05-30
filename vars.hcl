variable "PROJECT_ID" {
  validation {
    condition     = PROJECT_ID != ""
    error_message = "The variable 'PROJECT_ID' must not be empty."
  }
}

variable "LOCATION" {
  default = "europe-west1"
}

variable "REPO_NAME" {
  validation {
    condition     = REPO_NAME != ""
    error_message = "The variable 'PROJECT_ID' must not be empty."
  }
}

variable "IMAGE_TAG_VERSION_APP" {
  validation {
    condition     = IMAGE_TAG_VERSION_APP != ""
    error_message = "The variable 'PROJECT_ID' must not be empty."
  }
}

variable "IMAGE_TAG_VERSION_INFRA" {
  validation {
    condition     = IMAGE_TAG_VERSION_INFRA != ""
    error_message = "The variable 'PROJECT_ID' must not be empty."
  }
}

variable "REPO_URL" {
  default = "${LOCATION}-docker.pkg.dev/${PROJECT_ID}/${REPO_NAME}"
}




