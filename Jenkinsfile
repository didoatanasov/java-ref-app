def applicationName = "java-ref-app"
def openshiftProject = "borica-poc"
def registry = "registry.ibs.bg:6001/repository/docker"
def valuesFile = ""
def tag
def now = new Date().format('yyyyMMdd_HHmmss')
def commitId
def version
def ENVIRONMENT
def agentLabel
def openshiftAPIEndpoint = [];

pipeline {
    agent none

    tools {
        maven 'maven-3.8.1'
        jdk 'jdk11'

    }
    stages {
        stage('Set Environment') {
            agent none
            steps {
                script {
                    ENVIRONMENT = scm.branches[0].name.substring(scm.branches[0].name.lastIndexOf("/") + 1)
                    echo 'ENV:' + ENVIRONMENT
                    agentLabel = ENVIRONMENT.equalsIgnoreCase('master') || ENVIRONMENT.equalsIgnoreCase('preprod') ? 'prod' : 'test'
                }
            }
        }
        stage('Set Agent') {
            agent { label "$agentLabel && linux" }
            stages {
                stage('Init') {
                    steps {
                        script {
                            switch (ENVIRONMENT) {
                                case 'development':
                                    openshiftProject = 'dev-refapps'
                                    valuesFile = 'values_dev.yaml'
                                    openshiftAPIEndpoint = ['ocp.ibsbg.bg']
                                    break;
                                case 'test':
                                    openshiftProject = 'test-omni-fe'
                                    valuesFile = 'values_test.yaml'
                                    openshiftAPIEndpoint = ['ocp.ibsbg.bg']
                                    break
                                case 'preprod':
                                    openshiftProject = 'preprod-omni-fe'
                                    valuesFile = 'values_preprod.yaml'
                                    openshiftAPIEndpoint = ['ocp.ibsbg.bg']
                                    break
                                case 'master':
                                    openshiftProject = 'prod-omni-fe'
                                    valuesFile = 'values_prod.yaml'
                                    openshiftAPIEndpoint = ['ocp.ibsbg.bg']
                                    break
                                default:
                                    openshiftProject = 'dev-omni-fe'
                                    valuesFile = 'values_dev.yaml'
                                    openshiftAPIEndpoint = ['ocp.ibsbg.bg']

                            }
                            commitId = sh(returnStdout: true, script: 'git rev-parse --short HEAD')
                            version = (now + '_' + commitId).trim()

                            tag = registry + "/" + applicationName + ":" + version
                        }
                        sh "sed -i 's/appVersion:.*/appVersion: \"$version\"/g' helm/$applicationName/Chart.yaml"

                        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'devops', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {
                            sh 'docker login -u "$USERNAME" -p $PASSWORD ' + registry

                        }
                    }
                }
                stage('Build and Unit Test') {
                    steps {

                        withMaven(maven: 'maven-3.8.1') {
                            sh '''
    export MAVEN_OPTS="-Dmaven.wagon.http.ssl.insecure=true -Dmaven.wagon.http.ssl.allowall=true -Dmaven.wagon.http.ssl.ignore.validity.dates=true"
    mvn clean package verify
    '''
                        }
                    }
                }

                stage('Run static code analysis') {
                    environment {
                        scannerHome = tool 'sonar-scanner'
                    }
                    steps {

                        withSonarQubeEnv('Sonar') {

                            sh "${scannerHome}/bin/sonar-scanner"

                        }

                    }
                }


                stage('Check QualityGate') {
                    steps {
                        withSonarQubeEnv('Sonar') {
                            timeout(time: 10, unit: 'MINUTES') {
                                script {
                                    def qg = waitForQualityGate()
                                    if (qg.status != 'OK') {
                                        error 'Pipeline aborted due to quality gate failure: ${qg.status}'
                                    }

                                    echo 'Quality Gate Passed'
                                }
                            }
                        }
                    }
                }

                stage('Build Image') {
                    steps {

                        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'devops', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {
                            sh 'docker login -u "$USERNAME" -p $PASSWORD ' + registry
                            sh 'docker build . -t ' + tag

                        }
                    }

                }
                stage("Image security scan") {
                    steps {

                        sh '''
              docker start db || docker run -d --name db -p 5432:5432  arminc/clair-db && sleep 15

               # wait for db to come up
              docker start clair || docker run -d --name clair -p 6060:6060 --link db:postgres  arminc/clair-local-scan && sleep 1
              wget -qO clair-scanner https://registry.ibs.bg/repository/tools/clair-scanner_linux_amd64 && chmod +x clair-scanner
        '''
                        script {
                            DOCKER_GATEWAY = sh(returnStdout: true,
                                    script: 'docker network inspect bridge --format "{{range .IPAM.Config}}{{.Gateway}}{{end}}"')
                            DOCKER_GATEWAY = DOCKER_GATEWAY.trim();
                        }

                        sh "./clair-scanner -t Medium --report=clair_report.json --ip=${DOCKER_GATEWAY} $tag"

                    }
                }

                stage('Push Image to nexus') {
                    steps {
                        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'devops', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {

                            sh 'docker push ' + tag
                        }
                    }
                }

                stage('Deploy to OpenShift') {
                    steps {
                        withCredentials([[$class: 'UsernamePasswordMultiBinding', credentialsId: 'devops', usernameVariable: 'USERNAME', passwordVariable: 'PASSWORD']]) {
                            script {
                                openshiftAPIEndpoint.each { item ->
                                    sh "oc login -u $USERNAME -p $PASSWORD -s api.${item}:6443 --insecure-skip-tls-verify=true"
                                    sh "helm upgrade --install -n $openshiftProject -f helm/$applicationName/$valuesFile $applicationName --set service.routerCanonicalHostname=apps.${item}  ./helm/$applicationName"
                                    sh "oc logout"
                                }
                            }
                        }
                    }
                }
            }
            post {
                always {
                    echo 'Build completed'
                }
                success {
                    mail bcc: '', body: "<b>Build successful! </b><br>Project: ${env.JOB_NAME} <br>Build Number: ${env.BUILD_NUMBER} <br> URL of build: ${env.BUILD_URL}", charset: 'UTF-8', from: 'devops@ibs.bg', mimeType: 'text/html', replyTo: '', subject: "SUCCESS CI: Project name -> ${env.JOB_NAME}", to: " d.atanasov@ibs.bg";
                }
                failure {
                    mail bcc: '', body: "<b>Build failed!</b><br>Project: ${env.JOB_NAME} <br>Build Number: ${env.BUILD_NUMBER} <br> URL of build: ${env.BUILD_URL}",  charset: 'UTF-8', from: 'devops@ibs.bg', mimeType: 'text/html', replyTo: '', subject: "ERROR CI: Project name -> ${env.JOB_NAME}", to: "d.atanasov@ibs.bg";
                }
                unstable {
                    mail bcc: '', body: "<b>Build Unstable! </b><br>Project: ${env.JOB_NAME} <br>Build Number: ${env.BUILD_NUMBER} <br> URL of build: ${env.BUILD_URL}",  charset: 'UTF-8', from: 'devops@ibs.bg', mimeType: 'text/html', replyTo: '', subject: "UNSTABLE CI: Project name -> ${env.JOB_NAME}", to: "d.atanasov@ibs.bg";
                }
                changed {
                    mail bcc: '', body: "<b>Build State Changed! </b><br>Project: ${env.JOB_NAME} <br>Build Number: ${env.BUILD_NUMBER} <br> URL of build: ${env.BUILD_URL}",  charset: 'UTF-8', from: 'devops@ibs.bg', mimeType: 'text/html', replyTo: '', subject: "Changed state CI: Project name -> ${env.JOB_NAME}", to: "d.atanasov@ibs.bg";

                }
            }
        }
    }
}