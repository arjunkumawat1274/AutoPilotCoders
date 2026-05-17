@isTest
private class CreateSupportCaseActionTest {
    
    @testSetup
    static void setup() {
        // Create test Account
        Account testAccount = new Account(Name = 'Test Hospital');
        insert testAccount;
        
        // Create test Contact
        Contact testContact = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            Email = 'john.doe@testhospital.com',
            Phone = '555-1234',
            AccountId = testAccount.Id
        );
        insert testContact;
        
        // Create test Asset
        Asset testAsset = new Asset(
            Name = 'Test MRI Machine',
            SerialNumber = 'MRI-12345',
            AccountId = testAccount.Id
        );
        insert testAsset;
    }
    
    @isTest
    static void testCreateCase_NewContactAndAccount() {
        // Arrange
        CreateSupportCaseAction.CaseRequest request = new CreateSupportCaseAction.CaseRequest();
        request.fullName = 'Jane Smith';
        request.email = 'jane.smith@newhospital.com';
        request.phone = '555-5678';
        request.companyName = 'New Hospital';
        request.productName = 'CT Scanner';
        request.serialNumber = 'CT-67890';
        request.assetLocation = 'Building A, Floor 2';
        request.issueDescription = 'Scanner is producing blurry images';
        request.priority = 'High';
        request.whenStarted = 'Today morning';
        request.errorCodes = 'ERR-001, ERR-002';
        
        List<CreateSupportCaseAction.CaseRequest> requests = new List<CreateSupportCaseAction.CaseRequest>{request};
        
        // Act
        Test.startTest();
        List<CreateSupportCaseAction.CaseResult> results = CreateSupportCaseAction.createSupportCases(requests);
        Test.stopTest();
        
        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Case creation should succeed');
        System.assertNotEquals(null, results[0].caseNumber, 'Case number should be populated');
        System.assertNotEquals(null, results[0].caseId, 'Case ID should be populated');
        
        // Verify Case was created
        Case createdCase = [SELECT Id, Subject, Description, Origin, Status, Priority, ContactId, AccountId 
                           FROM Case WHERE Id = :results[0].caseId];
        System.assertEquals('Service Request: CT Scanner - Scanner is producing blurry images', createdCase.Subject);
        System.assertEquals('Experience Site Chatbot', createdCase.Origin);
        System.assertEquals('New', createdCase.Status);
        System.assertEquals('High', createdCase.Priority);
        System.assertNotEquals(null, createdCase.ContactId, 'Contact should be linked');
        System.assertNotEquals(null, createdCase.AccountId, 'Account should be linked');
        
        // Verify Contact was created
        Contact createdContact = [SELECT Id, FirstName, LastName, Email, AccountId 
                                 FROM Contact WHERE Id = :createdCase.ContactId];
        System.assertEquals('Jane', createdContact.FirstName);
        System.assertEquals('Smith', createdContact.LastName);
        System.assertEquals('jane.smith@newhospital.com', createdContact.Email);
        
        // Verify Account was created
        Account createdAccount = [SELECT Id, Name FROM Account WHERE Id = :createdCase.AccountId];
        System.assertEquals('New Hospital', createdAccount.Name);
    }
    
    @isTest
    static void testCreateCase_ExistingContactAndAccount() {
        // Arrange
        Contact existingContact = [SELECT Id, Email, AccountId FROM Contact LIMIT 1];
        Account existingAccount = [SELECT Id, Name FROM Account WHERE Id = :existingContact.AccountId];
        
        CreateSupportCaseAction.CaseRequest request = new CreateSupportCaseAction.CaseRequest();
        request.fullName = 'John Doe';
        request.email = existingContact.Email;
        request.phone = '555-1234';
        request.companyName = existingAccount.Name;
        request.productName = 'X-Ray Machine';
        request.assetLocation = 'Emergency Room';
        request.issueDescription = 'Machine is not powering on';
        request.priority = 'Critical';
        request.whenStarted = 'One hour ago';
        
        List<CreateSupportCaseAction.CaseRequest> requests = new List<CreateSupportCaseAction.CaseRequest>{request};
        
        Integer contactCountBefore = [SELECT COUNT() FROM Contact];
        Integer accountCountBefore = [SELECT COUNT() FROM Account];
        
        // Act
        Test.startTest();
        List<CreateSupportCaseAction.CaseResult> results = CreateSupportCaseAction.createSupportCases(requests);
        Test.stopTest();
        
        // Assert
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(true, results[0].success, 'Case creation should succeed');
        
        Integer contactCountAfter = [SELECT COUNT() FROM Contact];
        Integer accountCountAfter = [SELECT COUNT() FROM Account];
        
        System.assertEquals(contactCountBefore, contactCountAfter, 'No new Contact should be created');
        System.assertEquals(accountCountBefore, accountCountAfter, 'No new Account should be created');
        
        // Verify Case links to existing records
        Case createdCase = [SELECT Id, ContactId, AccountId FROM Case WHERE Id = :results[0].caseId];
        System.assertEquals(existingContact.Id, createdCase.ContactId, 'Should use existing Contact');
        System.assertEquals(existingAccount.Id, createdCase.AccountId, 'Should use existing Account');
    }
    
    @isTest
    static void testCreateCase_WithAssetLink() {
        // Arrange
        Asset existingAsset = [SELECT Id, SerialNumber FROM Asset LIMIT 1];
        
        CreateSupportCaseAction.CaseRequest request = new CreateSupportCaseAction.CaseRequest();
        request.fullName = 'Test User';
        request.email = 'test.user@hospital.com';
        request.phone = '555-9999';
        request.companyName = 'Hospital ABC';
        request.productName = 'MRI Scanner';
        request.serialNumber = existingAsset.SerialNumber;
        request.assetLocation = 'Radiology Department';
        request.issueDescription = 'Loud noise during scan';
        request.priority = 'Medium';
        request.whenStarted = 'Yesterday';
        
        List<CreateSupportCaseAction.CaseRequest> requests = new List<CreateSupportCaseAction.CaseRequest>{request};
        
        // Act
        Test.startTest();
        List<CreateSupportCaseAction.CaseResult> results = CreateSupportCaseAction.createSupportCases(requests);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, results[0].success, 'Case creation should succeed');
        
        Case createdCase = [SELECT Id, AssetId FROM Case WHERE Id = :results[0].caseId];
        System.assertEquals(existingAsset.Id, createdCase.AssetId, 'Asset should be linked to Case');
    }
    
    @isTest
    static void testCreateCase_BulkProcessing() {
        // Arrange - Create 10 requests
        List<CreateSupportCaseAction.CaseRequest> requests = new List<CreateSupportCaseAction.CaseRequest>();
        
        for (Integer i = 0; i < 10; i++) {
            CreateSupportCaseAction.CaseRequest request = new CreateSupportCaseAction.CaseRequest();
            request.fullName = 'Bulk User ' + i;
            request.email = 'bulk' + i + '@hospital.com';
            request.phone = '555-000' + i;
            request.companyName = 'Bulk Hospital ' + i;
            request.productName = 'Device ' + i;
            request.assetLocation = 'Location ' + i;
            request.issueDescription = 'Issue description for device ' + i;
            request.priority = 'Low';
            request.whenStarted = 'Today';
            requests.add(request);
        }
        
        // Act
        Test.startTest();
        List<CreateSupportCaseAction.CaseResult> results = CreateSupportCaseAction.createSupportCases(requests);
        Test.stopTest();
        
        // Assert
        System.assertEquals(10, results.size(), 'Should return 10 results');
        
        for (CreateSupportCaseAction.CaseResult result : results) {
            System.assertEquals(true, result.success, 'All cases should be created successfully');
            System.assertNotEquals(null, result.caseId, 'All cases should have IDs');
        }
        
        Integer caseCount = [SELECT COUNT() FROM Case WHERE Origin = 'Experience Site Chatbot'];
        System.assertEquals(10, caseCount, '10 cases should be created');
    }
    
    @isTest
    static void testCreateCase_LongDescription() {
        // Arrange - Test with description longer than 80 characters
        CreateSupportCaseAction.CaseRequest request = new CreateSupportCaseAction.CaseRequest();
        request.fullName = 'Test User';
        request.email = 'test@example.com';
        request.phone = '555-0000';
        request.companyName = 'Test Company';
        request.productName = 'Test Product';
        request.assetLocation = 'Test Location';
        request.issueDescription = 'This is a very long issue description that exceeds eighty characters and should be truncated in the subject line';
        request.priority = 'Medium';
        request.whenStarted = 'Today';
        
        List<CreateSupportCaseAction.CaseRequest> requests = new List<CreateSupportCaseAction.CaseRequest>{request};
        
        // Act
        Test.startTest();
        List<CreateSupportCaseAction.CaseResult> results = CreateSupportCaseAction.createSupportCases(requests);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, results[0].success);
        
        Case createdCase = [SELECT Id, Subject FROM Case WHERE Id = :results[0].caseId];
        System.assert(createdCase.Subject.length() <= 255, 'Subject should not exceed max length');
        System.assert(createdCase.Subject.contains('This is a very long issue description that exceeds eighty characters and sho'), 
                     'Subject should contain truncated description');
    }
    
    @isTest
    static void testCreateCase_SingleNameHandling() {
        // Arrange - Test with single name (no space)
        CreateSupportCaseAction.CaseRequest request = new CreateSupportCaseAction.CaseRequest();
        request.fullName = 'Madonna';
        request.email = 'madonna@example.com';
        request.phone = '555-0000';
        request.companyName = 'Test Company';
        request.productName = 'Test Product';
        request.assetLocation = 'Test Location';
        request.issueDescription = 'Test issue';
        request.priority = 'Low';
        request.whenStarted = 'Today';
        
        List<CreateSupportCaseAction.CaseRequest> requests = new List<CreateSupportCaseAction.CaseRequest>{request};
        
        // Act
        Test.startTest();
        List<CreateSupportCaseAction.CaseResult> results = CreateSupportCaseAction.createSupportCases(requests);
        Test.stopTest();
        
        // Assert
        System.assertEquals(true, results[0].success);
        
        Case createdCase = [SELECT Id, ContactId FROM Case WHERE Id = :results[0].caseId];
        Contact createdContact = [SELECT FirstName, LastName FROM Contact WHERE Id = :createdCase.ContactId];
        
        System.assertEquals('Madonna', createdContact.FirstName);
        System.assertEquals('Madonna', createdContact.LastName);
    }
    
    @isTest
    static void testCreateCase_CaseInsensitiveEmailMatch() {
        // Arrange
        Contact existingContact = [SELECT Id, Email FROM Contact LIMIT 1];
        
        CreateSupportCaseAction.CaseRequest request = new CreateSupportCaseAction.CaseRequest();
        request.fullName = 'Test User';
        request.email = existingContact.Email.toUpperCase(); // Use uppercase version
        request.phone = '555-0000';
        request.companyName = 'Test Company';
        request.productName = 'Test Product';
        request.assetLocation = 'Test Location';
        request.issueDescription = 'Test issue';
        request.priority = 'Low';
        request.whenStarted = 'Today';
        
        List<CreateSupportCaseAction.CaseRequest> requests = new List<CreateSupportCaseAction.CaseRequest>{request};
        
        Integer contactCountBefore = [SELECT COUNT() FROM Contact];
        
        // Act
        Test.startTest();
        List<CreateSupportCaseAction.CaseResult> results = CreateSupportCaseAction.createSupportCases(requests);
        Test.stopTest();
        
        // Assert
        Integer contactCountAfter = [SELECT COUNT() FROM Contact];
        System.assertEquals(contactCountBefore, contactCountAfter, 'Should not create duplicate Contact');
        
        Case createdCase = [SELECT ContactId FROM Case WHERE Id = :results[0].caseId];
        System.assertEquals(existingContact.Id, createdCase.ContactId, 'Should match existing Contact case-insensitively');
    }
    
    @isTest
    static void testCreateCase_DescriptionFormatting() {
        // Arrange
        CreateSupportCaseAction.CaseRequest request = new CreateSupportCaseAction.CaseRequest();
        request.fullName = 'Test User';
        request.email = 'test@example.com';
        request.phone = '555-1234';
        request.companyName = 'Test Hospital';
        request.productName = 'MRI Scanner';
        request.serialNumber = 'MRI-9999';
        request.assetLocation = 'Radiology';
        request.issueDescription = 'System error';
        request.priority = 'High';
        request.whenStarted = 'This morning';
        request.errorCodes = 'ERR-101, ERR-202';
        
        List<CreateSupportCaseAction.CaseRequest> requests = new List<CreateSupportCaseAction.CaseRequest>{request};
        
        // Act
        Test.startTest();
        List<CreateSupportCaseAction.CaseResult> results = CreateSupportCaseAction.createSupportCases(requests);
        Test.stopTest();
        
        // Assert
        Case createdCase = [SELECT Description FROM Case WHERE Id = :results[0].caseId];
        
        System.assert(createdCase.Description.contains('Product: MRI Scanner'), 'Description should contain product');
        System.assert(createdCase.Description.contains('Model/Serial Number: MRI-9999'), 'Description should contain serial');
        System.assert(createdCase.Description.contains('Asset Location: Radiology'), 'Description should contain location');
        System.assert(createdCase.Description.contains('Issue Description: System error'), 'Description should contain issue');
        System.assert(createdCase.Description.contains('Issue Started: This morning'), 'Description should contain when started');
        System.assert(createdCase.Description.contains('Error Codes: ERR-101, ERR-202'), 'Description should contain error codes');
        System.assert(createdCase.Description.contains('Customer: Test User'), 'Description should contain customer name');
        System.assert(createdCase.Description.contains('Email: test@example.com'), 'Description should contain email');
        System.assert(createdCase.Description.contains('Phone: 555-1234'), 'Description should contain phone');
        System.assert(createdCase.Description.contains('Company/Hospital: Test Hospital'), 'Description should contain company');
    }
}