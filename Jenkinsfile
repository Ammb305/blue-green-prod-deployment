pipeline {
    agent any

    tools {
        maven "maven3.9"
        jdk "JDK17"
    }
    
    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['blue', 'green'], description: 'Choose which environment to deploy: Blue or Green')
        choice(name: 'DOCKER_TAG', choices: ['blue', 'green'], description: 'Choose the Docker image tag for the deployment')
        booleanParam(name: 'SWITCH_TRAFFIC', defaultValue: false, description: 'Switch traffic between Blue and Green')
    }
    
    environment {
        IMAGE_NAME = "ammb/bankapp"
        TAG = "${params.DOCKER_TAG}"
        KUBE_NAMESPACE = 'jenkins'
        SCANNER_HOME = tool 'sonar-scanner'
        CURRENT_ENV = "${params.DEPLOY_ENV == 'blue' ? 'green' : 'blue'}"
        HEALTH_CHECK_URL = "http://bankapp-service.jenkins.svc.cluster.local:8080"
    }

    stages {
        stage('Git Checkout') {
            steps {
                git branch: 'main', credentialsId: 'b12602d9-c2a0-4a27-a55f-0eef7049cd19', url: 'https://github.com/Ammb305/blue-green-prod-deployment.git'
            }
        }

        stage('Maven Build') {
            steps {
                sh "mvn clean install -DskipTests"
            }
        }
        
        stage('SonarQube Analysis') {
            steps {
                withSonarQubeEnv('sonar') {
                    sh """
                    $SCANNER_HOME/bin/sonar-scanner \
                      -Dsonar.projectKey=nodejsmysql \
                      -Dsonar.projectName=nodejsmysql \
                      -Dsonar.sources=src/main/java \
                      -Dsonar.tests=src/test/java \
                      -Dsonar.java.binaries=target/classes
                    """
                }
            }
        }
        
        stage('Trivy File Scan') {
            steps {
                sh "trivy fs --format table -o fs.html ."
            }
        }
        
        stage('Docker Build') {
            steps {
                withDockerRegistry(credentialsId: 'docker-cred') {
                    sh "docker build -t ${IMAGE_NAME}:${TAG} ."
                }
            }
        }
        
        stage('Trivy Image Scan') {
            steps {
                sh "trivy image --format table -o image.html ${IMAGE_NAME}:${TAG}"
            }
        }
        
        stage('Docker Push Image') {
            steps {
                withDockerRegistry(credentialsId: 'docker-cred') {
                    sh "docker push ${IMAGE_NAME}:${TAG}"
                }
            }
        }
        
        stage('Deploy MySQL Deployment and its Service') {
            steps {
                withKubeConfig(caCertificate: '', clusterName: 'blue-green-cluster', contextName: '', credentialsId: 'k8s-token', namespace: 'jenkins', restrictKubeConfigAccess: false, serverUrl: 'https://A84F9034CF2E0E1BB4BEF6D0A4B85298.gr7.us-east-1.eks.amazonaws.com') {
                    sh "kubectl apply -f ./k8s/deployments/mysql-deployment.yml -n ${KUBE_NAMESPACE}"  
                }
            }
        }
        
        stage('Deploy App SVC') {
            steps {
                withKubeConfig(caCertificate: '', clusterName: 'blue-green-cluster', contextName: '', credentialsId: 'k8s-token', namespace: 'jenkins', restrictKubeConfigAccess: false, serverUrl: 'https://A84F9034CF2E0E1BB4BEF6D0A4B85298.gr7.us-east-1.eks.amazonaws.com') {
                    sh """
                    if ! kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}; then
                        kubectl apply -f ./k8s/deployments/bankapp-svc.yml -n ${KUBE_NAMESPACE}  
                    fi
                    """
                }
            }
        }
        
        stage('Deploy to Kubernetes') {
            steps {
                script {
                    def deploymentFile = params.DEPLOY_ENV == 'blue' ? './k8s/deployments/blue-app-deployment.yml' : './k8s/deployments/green-app-deployment.yml'
                    withKubeConfig(caCertificate: '', clusterName: 'blue-green-cluster', contextName: '', credentialsId: 'k8s-token', namespace: 'jenkins', restrictKubeConfigAccess: false, serverUrl: 'https://A84F9034CF2E0E1BB4BEF6D0A4B85298.gr7.us-east-1.eks.amazonaws.com') {
                        sh "kubectl apply -f ${deploymentFile} -n ${KUBE_NAMESPACE}"
                    }
                }
            }
        }
        
        stage('Switch Traffic Between (Blue / Green) Environment') {
            when {
                expression { return params.SWITCH_TRAFFIC }
            }
            steps {
                script {
                    def newEnv = params.DEPLOY_ENV
                    withKubeConfig(caCertificate: '', clusterName: 'blue-green-cluster', contextName: '', credentialsId: 'k8s-token', namespace: 'jenkins', restrictKubeConfigAccess: false, serverUrl: 'https://A84F9034CF2E0E1BB4BEF6D0A4B85298.gr7.us-east-1.eks.amazonaws.com') {
                        sh """
                        kubectl patch service bankapp-service -p '{\"spec\": {\"selector\": {\"app\": \"bankapp\", \"version\": \"${newEnv}\"}}} -n ${KUBE_NAMESPACE}'
                        """
                    }
                    echo "Traffic has been switched to the ${newEnv} environment."
                }
            }
        }
        
        stage('Health Check') {
            when {
                expression { return params.SWITCH_TRAFFIC }
            }
            steps {
                script {
                    def newEnv = params.DEPLOY_ENV
                    withKubeConfig(caCertificate: '', clusterName: 'blue-green-cluster', contextName: '', credentialsId: 'k8s-token', namespace: 'jenkins', restrictKubeConfigAccess: false, serverUrl: 'https://A84F9034CF2E0E1BB4BEF6D0A4B85298.gr7.us-east-1.eks.amazonaws.com') {
                        // Wait for pods to be ready
                        sh "kubectl wait --for=condition=ready pod -l version=${newEnv} -n ${KUBE_NAMESPACE} --timeout=120s"
                        
                        // Perform a health check
                        def healthCheck = sh(script: "curl -s -o /dev/null -w '%{http_code}' ${HEALTH_CHECK_URL}", returnStdout: true).trim()
                        if (healthCheck != "200") {
                            error "Health check failed for ${newEnv} environment. HTTP status: ${healthCheck}. Triggering rollback."
                        }
                    }
                }
            }
        }
        
        stage('Deployment Verification') {
            steps {
                script {
                    def verifyEnv = params.DEPLOY_ENV
                    withKubeConfig(caCertificate: '', clusterName: 'blue-green-cluster', contextName: '', credentialsId: 'k8s-token', namespace: 'jenkins', restrictKubeConfigAccess: false, serverUrl: 'https://A84F9034CF2E0E1BB4BEF6D0A4B85298.gr7.us-east-1.eks.amazonaws.com') {
                        sh """
                        kubectl get pods -l version=${verifyEnv} -n ${KUBE_NAMESPACE}
                        kubectl get svc bankapp-service -n ${KUBE_NAMESPACE}
                        """
                    }
                }
            }
        }
    }

    post {
        failure {
            stage('Automatic Rollback') {
                steps {
                    script {
                        echo "Deployment failed. Rolling back to ${CURRENT_ENV} environment."
                        withKubeConfig(caCertificate: '', clusterName: 'blue-green-cluster', contextName: '', credentialsId: 'k8s-token', namespace: 'jenkins', restrictKubeConfigAccess: false, serverUrl: 'https://A84F9034CF2E0E1BB4BEF6D0A4B85298.gr7.us-east-1.eks.amazonaws.com') {
                            sh """
                            kubectl patch service bankapp-service -p '{\"spec\": {\"selector\": {\"app\": \"bankapp\", \"version\": \"${CURRENT_ENV}\"}}} -n ${KUBE_NAMESPACE}'
                            """
                        }
                        echo "Traffic has been rolled back to the ${CURRENT_ENV} environment."
                    }
                }
            }
        }
    }
}