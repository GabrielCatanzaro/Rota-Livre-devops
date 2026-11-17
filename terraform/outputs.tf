output "url_mvp" {
  description = "URL pública do MVP"
  value       = "http://${aws_eip.mvp.public_ip}"
}

output "ip_publico" {
  value = aws_eip.mvp.public_ip
}

output "comando_ssh" {
  description = "Acesso SSH (labsuser.pem é a vockey baixada do Learner Lab)"
  value       = "ssh -i labsuser.pem ubuntu@${aws_eip.mvp.public_ip}"
}
