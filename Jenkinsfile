pipeline {
    agent any
    
    environment {
        BACKEND_IMAGE = "yassird/expense-manager-backend"
        FRONTEND_IMAGE = "yassird/expense-manager-frontend"
        BUILD_TAG = "${BUILD_ID}" // Use the Jenkins build ID as the tag
        DOCKER_STACK_FILE = 'docker-stack.yml' // Swarm-compatible compose file
        GCP_VM_USER = 'yassirdiri'
        GCP_VM_IP = '34.173.250.63'
        GCP_SSH_KEY_ID = 'yassirdiri' // Replace with your Jenkins SSH credentials ID
        SWARM_STACK_NAME = 'expense-manager' // Name of the Swarm stack
    }
    
    stages {
        stage('Docker Login') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'docker-credentials', usernameVariable: 'DOCKER_USERNAME', passwordVariable: 'DOCKER_PASSWORD')]) {
                    sh 'docker login -u $DOCKER_USERNAME -p $DOCKER_PASSWORD'
                }
            }
        }

        stage('Install Backend Dependencies') {
            steps {
                dir('backend') {
                    sh 'npm install'
                }
            }
        }

        stage('Run Backend Tests') {
            steps {
                dir('backend') {
                    sh 'npm test'
                }
            }
        }

        stage('Run Semgrep Analysis') {
            steps {
                sh '''
                    docker run --rm -v "${WORKSPACE}:/src" returntocorp/semgrep semgrep scan --config auto /src/backend
                    docker run --rm -v "${WORKSPACE}:/src" returntocorp/semgrep semgrep scan --config auto /src/frontend
                '''
            }
        }
        
        stage('Build Backend Docker Image') {
            steps {
                dir('backend') {
                    sh 'docker build -t ${BACKEND_IMAGE}:${BUILD_TAG} .'
                }
            }
        }
        
        stage('Build Frontend Docker Image') {
            steps {
                dir('frontend') {
                    sh 'docker build -t ${FRONTEND_IMAGE}:${BUILD_TAG} .'
                }
            }
        }
        
        stage('Push Docker Images') {
            steps {
                sh 'docker push ${BACKEND_IMAGE}:${BUILD_TAG}'
                sh 'docker push ${FRONTEND_IMAGE}:${BUILD_TAG}'
            }
        }

        stage('Update Docker Stack File') {
            steps {
                script {
                    def stackFile = readFile(DOCKER_STACK_FILE)
                    
                    // Escape dollar signs and brackets for Groovy string interpolation
                    def backendImagePattern = /(image: ${BACKEND_IMAGE}:)\S+/
                    def frontendImagePattern = /(image: ${FRONTEND_IMAGE}:)\S+/
                    
                    stackFile = stackFile.replaceAll(backendImagePattern, "\$1${BUILD_TAG}")
                    stackFile = stackFile.replaceAll(frontendImagePattern, "\$1${BUILD_TAG}")
                    
                    writeFile file: DOCKER_STACK_FILE, text: stackFile

                    // Print the updated docker-stack.yml file to the console
                    echo 'Updated docker-stack.yml file:'
                    sh 'cat ${DOCKER_STACK_FILE}'
                }
            }
        }

        stage('Deploy to GCP VM using Docker Swarm') {
            steps {
                script {
                    sshagent([GCP_SSH_KEY_ID]) {
                        // Copy updated stack file to the GCP VM
                        sh "scp -o StrictHostKeyChecking=no ${DOCKER_STACK_FILE} ${GCP_VM_USER}@${GCP_VM_IP}:~/"
                        
                        // Deploy the stack to Docker Swarm
                        sh '''
                            ssh -o StrictHostKeyChecking=no ${GCP_VM_USER}@${GCP_VM_IP} "
                                docker stack deploy -c ~/docker-stack.yml ${SWARM_STACK_NAME}
                            "
                        '''
                    }
                }
            }
        }
    }
    
    post {
        always {
            sh 'docker rmi ${BACKEND_IMAGE}:${BUILD_TAG} || true'
            sh 'docker rmi ${FRONTEND_IMAGE}:${BUILD_TAG} || true'
        }
        success {
            echo 'Build and deployment completed successfully!'
        }
        failure {
            echo 'Build or deployment failed. Please check the logs.'
        }
    }
}
