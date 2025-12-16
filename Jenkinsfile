pipeline {
    agent any

    environment {
        AWS_REGION     = 'ap-northeast-2'
        AWS_ACCOUNT_ID = '723165663216'
        ECR_REPO       = 'petclinic-3tier-dev-was'   // 👉 네가 만든 ECR 리포 이름
        IMAGE_TAG      = "build-${BUILD_NUMBER}"
        ECR_URI        = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                echo "Building Docker image..."
                docker build -t $ECR_URI:$IMAGE_TAG .
                '''
            }
        }

        stage('Login to ECR') {
            steps {
                sh '''
                echo "Logging in to ECR..."
                aws ecr get-login-password --region $AWS_REGION \
                  | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
                '''
            }
        }

        stage('Push to ECR') {
            steps {
                sh '''
                echo "Pushing image to ECR..."
                docker push $ECR_URI:$IMAGE_TAG
                '''
            }
        }
    }

    post {
        success {
            echo "✅ CI 성공: 이미지가 ECR에 푸시되었습니다."
            echo "Image: $ECR_URI:$IMAGE_TAG"
        }
        failure {
            echo "❌ CI 실패"
        }
    }
}
