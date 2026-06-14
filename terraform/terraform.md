To enter into ec2 rum ```ssh -i afridi-key.pem ec2-user@<IP_FROM_OUTPUT>```



to pause services instead of destroying them
```terraform apply -var="sleep_mode=true"```
this will pause EC2, ECS, EKS, lambda (not exactly pause sometimes its a stop, sometimes its no compute)