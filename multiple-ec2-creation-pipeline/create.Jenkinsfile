node("ec2-provisioner") {
  container("opentofu") {
    stage("Checkout") {
      checkout scm
    }

    dir("multiple-ec2-creation-pipeline/sample-ec2-modules/environments/uat/") {
      stage("Resolve customer config") {
        if (!(params.CUSTOMER_NAME ==~ /[a-z0-9-]+/)) {
          error("CUSTOMER_NAME must match ^[a-z0-9-]+\$, got: ${params.CUSTOMER_NAME}")
        }
        env.CUSTOMER_NAME = params.CUSTOMER_NAME

        if (!fileExists("customers/${params.CUSTOMER_NAME}.yaml")) {
          error("No customer config found at customers/${params.CUSTOMER_NAME}.yaml")
        }
      }

      withCredentials([usernamePassword(
        credentialsId: 'jenkins-aws-access-key',
        usernameVariable: 'AWS_ACCESS_KEY_ID',
        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
      )]) {
        stage("Init opentofu") {
          sh '''tofu init -input=false \
                -backend-config="key=uat/$CUSTOMER_NAME/terraform.tfstate"'''
        }

        stage("Plan opentofu") {
          sh 'tofu plan -var="customer_name=$CUSTOMER_NAME"'
        }
      }
    }
  }
}
