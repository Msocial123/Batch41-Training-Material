pipeline {
    agent any 

    parameters {
        string(name: 'VERSION', description: 'Enter the APP Version')
    }

    environment {
        AWS_ACCOUNT_ID = "909688465000"
        REGION = "ap-south-1"
        REPO_URI = "${AWS_ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/devops"
        DOCKER_IMAGE = "clahan-app-web:{VERSION}"
        DOCKER_REGISTRY = "docker.io"
        DOCKER_REGISTRY_CREDENCIALS = "docker_creds"
    }

    stages {
        stage('Clone') {
            steps {
                echo "Cloing the GitHub Repository"
                git url: 'https://github.com/Msocial123/Fitness_Tracker.git', branch: 'master'
            }
        }

        stage('Docker Build') {
            steps {
                echo "Building the Docker Image ${DOCKER_IMAGE}"
                sh "docker build -t ${DOCKER_IMAGE} ."
            }
        }

        stage('Push to ECR') {
            steps {
                script {
                    withAWS(credentials: 'aws_creds', region: "${REGION}") {
                        echo "Pushing the docker image to AWS ECR"
                        sh """
                            aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${REPO_URI}
                            docker tag ${DOCKER_IMAGE} ${REPO_URI}:${VERSION}
                            docker push ${REPO_URI}:${VERSION}
                        """
                    }
                }
            }
        } 
    }
}
