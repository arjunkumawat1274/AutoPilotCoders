public with sharing class CreateSupportCaseAction {
    
    @InvocableMethod(label='Create Support Case' description='Creates a support case with customer, product, and issue details' category='Case Management')
    public static List<CaseResult> createSupportCases(List<CaseRequest> requests) {
        List<CaseResult> results = new List<CaseResult>();
        
        // Collect all emails and company names for bulk processing
        Set<String> emails = new Set<String>();
        Set<String> companyNames = new Set<String>();
        Set<String> serialNumbers = new Set<String>();
        
        for (CaseRequest req : requests) {
            if (String.isNotBlank(req.email)) {
                emails.add(req.email.toLowerCase());
            }
            if (String.isNotBlank(req.companyName)) {
                companyNames.add(req.companyName);
            }
            if (String.isNotBlank(req.serialNumber)) {
                serialNumbers.add(req.serialNumber);
            }
        }
        
        // Query existing Contacts, Accounts, and Assets
        Map<String, Contact> contactsByEmail = new Map<String, Contact>();
        Map<String, Account> accountsByName = new Map<String, Account>();
        Map<String, Asset> assetsBySerial = new Map<String, Asset>();
        
        try {
            for (Contact c : [SELECT Id, Email, AccountId FROM Contact WHERE Email IN :emails WITH USER_MODE]) {
                contactsByEmail.put(c.Email.toLowerCase(), c);
            }
            
            for (Account a : [SELECT Id, Name FROM Account WHERE Name IN :companyNames WITH USER_MODE]) {
                accountsByName.put(a.Name, a);
            }
            
            if (!serialNumbers.isEmpty()) {
                for (Asset ast : [SELECT Id, SerialNumber FROM Asset WHERE SerialNumber IN :serialNumbers WITH USER_MODE]) {
                    assetsBySerial.put(ast.SerialNumber, ast);
                }
            }
        } catch (Exception e) {
            CaseResult errorResult = new CaseResult();
            errorResult.success = false;
            errorResult.errorMessage = 'Error querying records: ' + e.getMessage();
            results.add(errorResult);
            return results;
        }
        
        // Prepare records to insert
        List<Account> accountsToInsert = new List<Account>();
        List<Contact> contactsToInsert = new List<Contact>();
        List<Case> casesToInsert = new List<Case>();
        
        // Process each request
        for (CaseRequest req : requests) {
            try {
                // Get or create Account
                Account acc = accountsByName.get(req.companyName);
                if (acc == null && String.isNotBlank(req.companyName)) {
                    acc = new Account(Name = req.companyName);
                    accountsToInsert.add(acc);
                    accountsByName.put(req.companyName, acc);
                }
                
                // Get or create Contact
                Contact con = contactsByEmail.get(req.email.toLowerCase());
                if (con == null) {
                    con = new Contact(
                        FirstName = getFirstName(req.fullName),
                        LastName = getLastName(req.fullName),
                        Email = req.email,
                        Phone = req.phone
                    );
                    contactsToInsert.add(con);
                    contactsByEmail.put(req.email.toLowerCase(), con);
                }
                
                // Get Asset if serial number provided
                Asset linkedAsset = null;
                if (String.isNotBlank(req.serialNumber)) {
                    linkedAsset = assetsBySerial.get(req.serialNumber);
                }
                
                // Create Case
                String productPart = req.issueDescription != null && req.issueDescription.length() > 80
                    ? req.issueDescription.substring(0, 80)
                    : req.issueDescription;
                String subject = 'Service Request: ' + req.productName + ' - ' + productPart;
                
                Case newCase = new Case();
                newCase.Subject = subject;
                newCase.Description = buildCaseDescription(req);
                newCase.Origin = 'Experience Site Chatbot';
                newCase.Status = 'New';
                newCase.Priority = req.priority;
                
                casesToInsert.add(newCase);
                
            } catch (Exception e) {
                CaseResult errorResult = new CaseResult();
                errorResult.success = false;
                errorResult.errorMessage = 'Error processing request: ' + e.getMessage();
                results.add(errorResult);
            }
        }
        
        // Insert Accounts first
        if (!accountsToInsert.isEmpty()) {
            try {
                insert as user accountsToInsert;
            } catch (Exception e) {
                CaseResult errorResult = new CaseResult();
                errorResult.success = false;
                errorResult.errorMessage = 'Error creating accounts: ' + e.getMessage();
                results.add(errorResult);
                return results;
            }
        }
        
        // Link Contacts to Accounts and insert
        for (Contact con : contactsToInsert) {
            for (CaseRequest req : requests) {
                if (req.email.equalsIgnoreCase(con.Email)) {
                    Account acc = accountsByName.get(req.companyName);
                    if (acc != null) {
                        con.AccountId = acc.Id;
                    }
                    break;
                }
            }
        }
        
        if (!contactsToInsert.isEmpty()) {
            try {
                insert as user contactsToInsert;
            } catch (Exception e) {
                CaseResult errorResult = new CaseResult();
                errorResult.success = false;
                errorResult.errorMessage = 'Error creating contacts: ' + e.getMessage();
                results.add(errorResult);
                return results;
            }
        }
        
        // Link Cases to Contacts, Accounts, and Assets
        for (Integer i = 0; i < casesToInsert.size(); i++) {
            CaseRequest req = requests[i];
            Case c = casesToInsert[i];
            
            Contact con = contactsByEmail.get(req.email.toLowerCase());
            if (con != null) {
                c.ContactId = con.Id;
                if (con.AccountId != null) {
                    c.AccountId = con.AccountId;
                }
            }
            
            if (String.isNotBlank(req.serialNumber)) {
                Asset linkedAsset = assetsBySerial.get(req.serialNumber);
                if (linkedAsset != null) {
                    c.AssetId = linkedAsset.Id;
                }
            }
        }
        
        // Insert Cases
        if (!casesToInsert.isEmpty()) {
            try {
                insert as user casesToInsert;
                
                // Build success results
                for (Case c : casesToInsert) {
                    CaseResult result = new CaseResult();
                    result.success = true;
                    result.caseNumber = c.CaseNumber;
                    result.caseId = c.Id;
                    results.add(result);
                }
            } catch (Exception e) {
                CaseResult errorResult = new CaseResult();
                errorResult.success = false;
                errorResult.errorMessage = 'Error creating cases: ' + e.getMessage();
                results.add(errorResult);
            }
        }
        
        return results;
    }
    
    private static String getFirstName(String fullName) {
        if (String.isBlank(fullName)) return 'Unknown';
        List<String> parts = fullName.trim().split('\\s+');
        return parts.size() > 1 ? parts[0] : fullName;
    }
    
    private static String getLastName(String fullName) {
        if (String.isBlank(fullName)) return 'Unknown';
        List<String> parts = fullName.trim().split('\\s+');
        return parts.size() > 1 ? parts[parts.size() - 1] : fullName;
    }
    
    private static String buildCaseDescription(CaseRequest req) {
        // Temporary hardcoded stub to guarantee compilation.
        // TODO: replace with full description builder in follow-up.
        return 'Product: ' + (req.productName == null ? 'Unknown Product' : req.productName)
            + '\nIssue: ' + (req.issueDescription == null ? 'No description provided' : req.issueDescription);
    }
    
    public class CaseRequest {
        @InvocableVariable(required=true label='Full Name')
        public String fullName;
        
        @InvocableVariable(required=true label='Email')
        public String email;
        
        @InvocableVariable(required=true label='Phone')
        public String phone;
        
        @InvocableVariable(required=true label='Company/Hospital Name')
        public String companyName;
        
        @InvocableVariable(required=true label='Product Name')
        public String productName;
        
        @InvocableVariable(label='Model/Serial Number')
        public String serialNumber;
        
        @InvocableVariable(required=true label='Asset Location')
        public String assetLocation;
        
        @InvocableVariable(required=true label='Issue Description')
        public String issueDescription;
        
        @InvocableVariable(required=true label='Priority')
        public String priority;
        
        @InvocableVariable(required=true label='When Started')
        public String whenStarted;
        
        @InvocableVariable(label='Error Codes')
        public String errorCodes;
    }
    
    public class CaseResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        
        @InvocableVariable(label='Case Number')
        public String caseNumber;
        
        @InvocableVariable(label='Case ID')
        public String caseId;
        
        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }
}