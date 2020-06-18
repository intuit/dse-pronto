resource "aws_s3_bucket_object" "bucket-object" {
  bucket = var.bucket_name
  key    = var.key_prefix
  source = var.file_source
  etag   = md5(file("${var.file_source}"))
}
