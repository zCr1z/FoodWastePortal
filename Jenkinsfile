pipeline {
    agent any
    options {
        timestamps()
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }
    parameters {
        booleanParam(name: 'SIMULATE_BAD_RELEASE', defaultValue: false,
                     description: 'Deploy a deliberately nonexistent image tag to demonstrate automatic rollback.')
    }
    environment {
        // Replace with your Docker Hub username/repository.
        IMAGE_REPO = 'YOUR_DOCKERHUB_USERNAME/foodwasteportal'
        K8S_DEPLOYMENT = 'foodwasteportal'
        K8S_NAMESPACE = 'default'
        DOCKER_CREDENTIALS_ID = 'dockerhub-creds'
        KUBECONFIG_CREDENTIALS_ID = 'kubeconfig'
    }
    stages {
        stage('Checkout') {
            steps { checkout scm }
        }
        stage('Validate Portal') {
            steps {
                script {
                    if (!fileExists('index.html') || !fileExists('Dockerfile') ||
                        !fileExists('deployment.yaml')) {
                        error('Required project files are missing.')
                    }
                    def html = readFile('index.html')
                    if (!html.contains('Surplus Food Redistribution Portal') ||
                        !html.contains('Redistributed')) {
                        error('Portal content validation failed.')
                    }
                    echo 'Portal files and required dashboard content validated.'
                }
            }
        }
        stage('Parallel Checks') {
            parallel {
                stage('HTML / Content Check') {
                    steps {
                        script {
                            def html = readFile('index.html')
                            ['Available', 'Reserved', 'Collected', 'Redistributed',
                             'Collection deadline', 'Pickup location'].each { phrase ->
                                if (!html.contains(phrase)) {
                                    error("Missing expected portal content: ${phrase}")
                                }
                            }
                            echo 'Content checks passed.'
                        }
                    }
                }
                stage('Kubernetes Manifest Check') {
                    steps {
                        script {
                            def manifest = readFile('deployment.yaml')
                            if (!manifest.contains('kind: Deployment') ||
                                !manifest.contains('kind: Service') ||
                                !manifest.contains('IMAGE_PLACEHOLDER')) {
                                error('Kubernetes manifest is incomplete.')
                            }
                            echo 'Manifest structure checks passed.'
                        }
                    }
                }
            }
        }
        stage('Build Docker Image') {
            steps {
                script {
                    env.BUILT_IMAGE = "${env.IMAGE_REPO}:${env.BUILD_NUMBER}"
                    bat 'docker version'
                    bat "docker build --pull -t ${env.BUILT_IMAGE} ."
                    bat "docker tag ${env.BUILT_IMAGE} ${env.IMAGE_REPO}:latest"
                }
            }
        }
        stage('Local Container Smoke Test') {
            steps {
                script {
                    bat 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference=\'Stop\'; docker rm -f fwp-smoke 2>$null; docker run -d --name fwp-smoke -p 18081:80 $env:BUILT_IMAGE; try { $ok=$false; for($i=0;$i -lt 15;$i++){ try { $r=Invoke-WebRequest http://localhost:18081 -UseBasicParsing -TimeoutSec 2; if($r.StatusCode -eq 200 -and $r.Content.Contains(\'Surplus Food Redistribution Portal\')){$ok=$true;break} } catch {}; Start-Sleep -Seconds 2 }; if(-not $ok){docker logs fwp-smoke; throw \'Smoke test failed\'}; Write-Host \'HTTP smoke test passed\' } finally { docker rm -f fwp-smoke 2>$null }"'
                }
            }
        }
        stage('Push Image to Docker Hub') {
            steps {
                withCredentials([usernamePassword(credentialsId: "${DOCKER_CREDENTIALS_ID}",
                    usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_TOKEN')]) {
                    bat 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$env:DOCKER_TOKEN | docker login -u $env:DOCKER_USER --password-stdin; if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; docker push $env:BUILT_IMAGE; if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; docker push $env:IMAGE_REPO`:latest; if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; docker logout"'
                }
            }
        }
        stage('Deploy and Verify / Roll Back if Faulty') {
            steps {
                withCredentials([file(credentialsId: "${KUBECONFIG_CREDENTIALS_ID}",
                                      variable: 'KUBECONFIG_FILE')]) {
                    script {
                        def imageToDeploy = env.BUILT_IMAGE
                        if (params.SIMULATE_BAD_RELEASE) {
                            imageToDeploy = "${env.IMAGE_REPO}:intentionally-missing-${env.BUILD_NUMBER}"
                            echo "DEMO MODE: deploying deliberately nonexistent image ${imageToDeploy}"
                        }
                        writeFile file: 'deployment.rendered.yaml',
                                  text: readFile('deployment.yaml').replace('IMAGE_PLACEHOLDER', imageToDeploy)
                        withEnv(["KUBECONFIG=${env.KUBECONFIG_FILE}"]) {
                            bat 'kubectl apply -f deployment.rendered.yaml'
                            int rolloutStatus = bat(returnStatus: true,
                                script: 'kubectl rollout status deployment/%K8S_DEPLOYMENT% --timeout=90s')
                            if (rolloutStatus != 0) {
                                echo 'Rollout failed. Showing deployment/pod diagnostics before rollback.'
                                bat 'kubectl get deployment,pods -l app=foodwasteportal -o wide'
                                bat 'kubectl describe deployment %K8S_DEPLOYMENT%'
                                int rollbackStatus = bat(returnStatus: true,
                                    script: 'kubectl rollout undo deployment/%K8S_DEPLOYMENT%')
                                if (rollbackStatus != 0) {
                                    error('Rollout failed and kubectl rollback also failed.')
                                }
                                int restoredStatus = bat(returnStatus: true,
                                    script: 'kubectl rollout status deployment/%K8S_DEPLOYMENT% --timeout=90s')
                                if (restoredStatus != 0) {
                                    error('Rollback command ran, but the previous release did not become ready.')
                                }
                                bat 'kubectl get deployment,pods -l app=foodwasteportal -o wide'
                                bat 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$r=Invoke-WebRequest http://localhost:30081 -UseBasicParsing -TimeoutSec 10; if($r.StatusCode -ne 200 -or -not $r.Content.Contains(\'Surplus Food Redistribution Portal\')){throw \'Restored portal HTTP verification failed\'}; Write-Host \'Rollback verification passed: portal returns HTTP 200\'"'
                                if (params.SIMULATE_BAD_RELEASE) {
                                    echo 'EXPECTED DEMO RESULT: faulty rollout detected, stable release restored and verified.'
                                } else {
                                    error('Deployment failed; rollback restored the previous version. Marking build failed for visibility.')
                                }
                            } else {
                                bat 'kubectl get deployment,pods -l app=foodwasteportal -o wide'
                                bat 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$r=Invoke-WebRequest http://localhost:30081 -UseBasicParsing -TimeoutSec 10; if($r.StatusCode -ne 200 -or -not $r.Content.Contains(\'Surplus Food Redistribution Portal\')){throw \'Deployed portal HTTP verification failed\'}; Write-Host \'Deployment verification passed: portal returns HTTP 200\'"'
                            }
                        }
                    }
                }
            }
        }
        stage('Archive Build Evidence') {
            steps {
                archiveArtifacts artifacts: 'index.html,Dockerfile,deployment.yaml,deployment.rendered.yaml',
                                 allowEmptyArchive: true
            }
        }
    }
    post {
        always {
            echo 'FoodWastePortal pipeline finished. Review the stages above for build, test, deployment, and rollback evidence.'
        }
    }
}
