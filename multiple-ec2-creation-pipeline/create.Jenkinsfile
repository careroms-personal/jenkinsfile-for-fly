node("ec2-provisioner") {
  container("opentofu") {
    stage("Checkout") {
      checkout scm
    }

    dir("multiple-ec2-creation-pipeline/") {
      def pipelineDir = pwd()

      stage("Resolve customer config") {
        if (!(params.CUSTOMER_NAME ==~ /[a-z0-9-]+/)) {
          error("CUSTOMER_NAME must match ^[a-z0-9-]+\$, got: ${params.CUSTOMER_NAME}")
        }
        env.CUSTOMER_NAME = params.CUSTOMER_NAME
        env.VAR_FILE = "${pipelineDir}/customer-configs/${params.CUSTOMER_NAME}.tfvars"

        if (!fileExists(env.VAR_FILE)) {
          error("No customer config found at ${env.VAR_FILE}")
        }
      }

      dir("sample-ec2-modules/environments/uat/") {
        withCredentials([usernamePassword(
          credentialsId: 'jenkins-aws-access-key',
          usernameVariable: 'AWS_ACCESS_KEY_ID',
          passwordVariable: 'AWS_SECRET_ACCESS_KEY'
        )]) {
          stage("Init opentofu") {
            sh '''opentofu init -reconfigure \
                  -backend-config="key=uat/$CUSTOMER_NAME/terraform.tfstate" \
                  -backend-config="encrypt=true"'''
          }

          stage("Plan opentofu") {
            sh 'opentofu plan -var-file="$VAR_FILE"'
          }
        }
      }
    }
  }
}
