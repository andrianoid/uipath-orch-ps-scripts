## >>>>>>>>>>>>>>>>>>> ########################################################
## >>>>>>>>>>>>>>>>>>> ########################################################
## >>>>>>>>>>>>>>>>>>> ########################################################

$config = Get-Content -Raw -Path config.json | ConvertFrom-Json

## >>>>>>>>>>>>>>>>>>> ########################################################
##
## Get Access Token
##
$accessTokenParams = @{
	grant_type='client_credentials';
	client_id=$config.clientId;
	client_secret=$config.client_secret;
	scope=$config.scopes
}
$tokenResponse = Invoke-WebRequest `
	-Uri $config.tokenUrl `
	-Method POST `
	-Body $accessTokenParams `
	-ContentType application/x-www-form-urlencoded
$temp = $tokenResponse.Content | ConvertFrom-Json
$access_token = $temp.access_token



## >>>>>>>>>>>>>>>>>>> ########################################################
##
## Get Folder Id
##
$folderUrl = $config.baseUrl + "odata/Folders";
$headers = @{
	"Authorization" = "Bearer $access_token"
	"ContentType" = "application/json"
	"Accept" = "application/json"
}
$folderResponse = Invoke-WebRequest `
	-Uri $folderUrl `
	-Method GET `
	-Headers $headers `
	-ContentType application/x-www-form-urlencoded 
$temp = $folderResponse.Content | ConvertFrom-Json
foreach($folder in $temp.value){
	if($folder.DisplayName.equals($config.folderName)){
		$folderId = $folder.id
	}
}
### Add a header for folder(/org) ID
$headers += @{
	"X-UIPATH-OrganizationUnitId" = "$folderId"
}

## >>>>>>>>>>>>>>>>>>> ########################################################
##
## Get Release
##
$releaseUrl = $config.baseUrl + "odata/Releases";
$releaseResponse = Invoke-WebRequest `
	-Uri $releaseUrl `
	-Method GET `
	-Headers $headers
$temp = $releaseResponse.Content | ConvertFrom-Json
foreach($release in $temp.value){
	## These are for test package
	if($release.ProcessKey.equals($config.testPackageIdentifier)){
		
		$releaseId = $release.Id;
		$releaseVersion = $release.ProcessVersion;
	}
	## These are for prod process/job release key
	if($release.ProcessKey.equals($config.processPackageIdentifier)){
		$releaseKey = $release.Key;
	}
}



	Write-Host "Test successful. Running Job"
	## >>>>>>>>>>>>>>>>>>> ########################################################
	##
	## Start Job
	##
	$jobExecutionUrl = $config.baseUrl + "odata/Jobs/UiPath.Server.Configuration.OData.StartJobs";
	$jobParams = @{
		startInfo=@{
			ReleaseKey=$releaseKey;
			Strategy="ModernJobsCount";
			JobsCount=1;
			Source="IntegrationTrigger";
			RuntimeType="NonProduction";
		}
	}
	$body = $jobParams | ConvertTo-Json

	$jobResponse = Invoke-WebRequest `
		-Uri $jobExecutionUrl `
		-Method POST `
		-Body $body `
		-Headers $headers `
		-ContentType "application/json"
	$temp = $jobResponse.Content | ConvertFrom-Json
	Write-Host "Job Started (" $temp.value.Key ")"

