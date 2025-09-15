@echo off
:MENU
cls
echo ===========================================
echo       Kind Cluster Full Management Menu
echo ===========================================
echo 1. Create Kind cluster haskind and namespace 'has'
echo 2. Deploy Apache deployment with 2 replicas and NodePort 31000
echo 3. Install Argo CD using Helm
echo 4. Delete Kind cluster haskind
echo 5. Exit
echo ===========================================
set /p choice=Enter your choice (1-5): 

if "%choice%"=="1" goto CREATE
if "%choice%"=="2" goto DEPLOY_APACHE
if "%choice%"=="3" goto INSTALL_ARGOCD
if "%choice%"=="4" goto DELETE
if "%choice%"=="5" exit
goto MENU

:CREATE
echo Creating Kind cluster 'haskind'...
kind create cluster --config kind-config.yaml
if errorlevel 1 (
    echo Failed to create Kind cluster. Please ensure Kind is installed and try again.
    pause
    goto MENU
)                           


echo Creating namespace 'has'...
kubectl create namespace has

echo.
echo Checking nodes...
kubectl get nodes

echo.
echo Checking pods in namespace 'has'...
kubectl get pods -n has

pause
goto MENU

:DEPLOY_APACHE
echo Deploying Apache deployment with 2 replicas in namespace 'has'...
kubectl create deployment apache-deploy --image=httpd --replicas=2 -n has

echo.
echo Exposing deployment as NodePort service on port 80 with NodePort 31000...
kubectl expose deployment apache-deploy --type=NodePort --name=apache-service --port=80 --target-port=80 -n has
kubectl patch service apache-service -n has -p "{\"spec\":{\"ports\":[{\"port\":80,\"nodePort\":31000,\"protocol\":\"TCP\"}]}}"

echo.
echo Checking pods in namespace 'has'...
kubectl get pods -n has

echo.
echo Checking services in namespace 'has'...
kubectl get svc -n has

pause
goto MENU

:INSTALL_ARGOCD
echo Installing Argo CD using Helm in namespace 'argocd'...
kubectl create namespace argocd

REM Add Argo CD Helm repo
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

REM Install Argo CD
helm install argocd argo/argo-cd -n argocd

echo.
echo Checking Argo CD pods in namespace 'argocd'...
kubectl get pods -n argocd

echo.
echo Argo CD installation complete!
pause
goto MENU

:DELETE
echo Deleting Kind cluster 'haskind'...
kind delete cluster --name haskind

echo.
echo Cluster deleted successfully!
pause
goto MENU
