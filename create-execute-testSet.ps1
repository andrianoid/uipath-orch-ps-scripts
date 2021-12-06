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

## >>>>>>>>>>>>>>>>>>> ########################################################
##
## Get TestCaseDefinitions
##
$testCaseDefUrl = $config.baseUrl + "odata/TestCaseDefinitions";
$testCaseDefResponse = Invoke-WebRequest `
	-Uri $testCaseDefUrl `
	-Method GET `
	-Headers $headers
$temp = $testCaseDefResponse.Content | ConvertFrom-Json
$caseIds = @()
foreach($testCase in $temp.value){
	if($testCase.PackageIdentifier.equals($config.testPackageIdentifier)){
		$caseIds += $testCase.Id
	}
}

## >>>>>>>>>>>>>>>>>>> ########################################################
##
## Create Test Set
##
Write-Host "Creating Test Set..."
$testSetUrl = $config.baseUrl + 'odata/TestSets';
$testSetName = $config.testSetName
$packageIdentifier = $config.testPackageIdentifier
$versionMask = $config.versionMask
$createTestSetParams = @{
	Name="$testSetName"; # -<pull-request>-<commitId>
	Description="Description"
	Packages=@(@{
		PackageIdentifier="$packageIdentifier";
		VersionMask="$versionMask";
		IncludePrerelease=$False;
	});
	TestCases=@();
	InputArguments=@();
	EnableCoverage=$False;
}
## Add to testCases for each caseId
foreach($caseId in $caseIds){
	$createTestSetParams.TestCases += @{
		Enabled=$True;
		VersionNumber="$releaseVersion";
		ReleaseId=$releaseId;
		DefinitionId=$caseId;
	}
}
$body = $createTestSetParams | ConvertTo-Json

$testSetResponse = Invoke-WebRequest `
	-Uri $testSetUrl `
	-Method POST `
	-Body $body `
	-Headers $headers `
	-ContentType "application/json"
$temp = $testSetResponse.Content | ConvertFrom-Json
$testSetKey = $temp.Key
$testSetId = $temp.Id
Write-Host "Test Set Created: '$($temp.Name)' (Key:$($temp.Key))(ID:$($temp.Id))"


## >>>>>>>>>>>>>>>>>>> ########################################################
##
## Run Test Set
##

Write-Host "Running Tests..."

$testExecutionUrl = $config.baseUrl + "api/TestAutomation/StartTestSetExecution?testSetKey=$testSetKey";
$testSetResponse = Invoke-WebRequest `
	-Uri $testExecutionUrl `
	-Method POST `
	-Headers $headers `
	-ContentType "application/json"
$testExecutionKey = $testSetResponse.Content
Write-Host "Test Execution ID: $testExecutionKey"

$testStatus = "Pending"
Do
{

## Wait for test set to be complete....
	## Wait a few seconds
	## Make call to get status of test execution
	$testExecutionStatusUrl = $config.baseUrl + "odata/TestSetExecutions($testExecutionKey)";
	$testStatusResponse = Invoke-WebRequest -Uri $testExecutionStatusUrl -Method GET -Headers $headers -ContentType "application/json"
	$temp = $testStatusResponse.Content | ConvertFrom-Json
	$testStatus = $temp.Status
	
	"Status: $testStatus... checking again in 5 seconds"
	
	if(!$testStatus.equals('Passed')){
		## Wait before retry
		Start-Sleep -s 5
	}

} While ($testStatus.equals('Pending') -or $testStatus.equals('Running'))
