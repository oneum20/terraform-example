## Diagram
```Mermaid
graph TD
  subgraph aws
		direction LR
		A[CloudFront - 'CDN'] --> B
		A --> C
	
		subgraph VPC
			subgraph AZ-A
				B[S3] 
				C[ELB] --> D
				D[EC2] --> E
				E[RDS - Master]
			end
			E --> F
			subgraph AZ-B
				F[RDS - Standby]
			end	
		end
	end
```