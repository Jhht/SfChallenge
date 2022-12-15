public with sharing class csvToRecord {
    
    @InvocableMethod(label='Convert upload csv to campaing members')
    public static List<List<String>> createRecords(List<Request> req){
           
        List<String> campaignRet = new List<String>();
       	List<List<String>> ret = new List<List<String>>();
            
        System.debug('req ' + req);
        
        List<ContentVersion> docs = new List<ContentVersion>([Select id,VersionData FROM ContentVersion WHERE ContentDocumentId =: req.get(0).ids ]);
        
        for(ContentVersion cv : docs){
            //getting data from file
            blob b = cv.VersionData;
            //convert data to string to process csv
            String strCSVFile = EncodingUtil.base64Decode(EncodingUtil.base64Encode(b)).toString();
            strCSVFile = strCSVFile.replaceAll(',"""', ',"DBLQT').replaceall('""",', 'DBLQT",');
            strCSVFile = strCSVFile.replaceAll('""', 'DBLQT');
            List<String> strCSVLines = new List<String>();
            strCSVLines = strCSVFile.split('\n');
            
            //getting campaings in map to avoid querys inside loop
            Map<String, Campaign> mapCamps = new  Map<String, Campaign>();           
            List<Campaign> camps = new List<Campaign>([Select id,name from Campaign where name IN ('BPMN Training', 'DMN Training')]);
            
            for( Campaign c  : camps){
                mapCamps.put(c.name.replaceAll('(\\s+)', ''), c);//delete empty space to avoid errors
            }            
            System.debug('mapCamps ' + mapCamps );
            
            List<CampaignMember> campMembInsert = new List<CampaignMember>();
            for(String s : strCSVLines){
                if(!s.contains('FirstName') &&  !s.contains('LastName') &&  !s.contains('Email')  &&  !s.contains('Training Date') &&  !s.contains('Training Name') ){//avoid headers
                    List<String> fields = new List<String>();
                    fields = s.split(',');
                    system.debug('att@@'+fields.get(0) + ' ' + fields.get(1) + ' ' + fields.get(2));
                    
                    if(fields.size() == 5){//assuming every row in csv is well formed, if not is not processed
                                          
                        String firstName = fields.get(0);
                        String lastName= fields.get(1);
                        String email= fields.get(2);
                        String trainDate= fields.get(3);
                        String trainName= fields.get(4);
                        
                        //checking dup on contact
                        List<Contact> dupContacts = hasDupContact(new Contact(FirstName = firstName, LastName = lastName, Email = email));
                        List<Lead> dupLeads = hasDupLead(new Lead(FirstName = firstName, LastName = lastName, Email = email));
                        
                        System.debug('dupContacts ' + dupContacts);
                        System.debug('dupLeads ' + dupLeads);
                        
                        Campaign c = mapCamps.get(String.valueOf(trainName.replaceAll('(\\s+)', '')));
                        
                        //checking dups
                        if(dupContacts.size() == 0 && dupLeads.size() == 0){
                            try{
                                Database.SaveResult sr = Database.insert(new Contact(FirstName = FirstName, LastName =LastName, Email = Email, Accountid = req.get(0).recordId));
                                if(sr.isSuccess()){
                                    System.debug('Cmp name ' +fields.get(4) );
                                    
                                    CampaignMember cm= New CampaignMember(CampaignId= c.id, ContactId= sr.getId(), Status='Received', Training_date__c = trainDate != null ? Date.valueOf(trainDate) : null); 
                                    campMembInsert.add(cm);
                                }
                            }catch(Exception e){
                               System.debug('Error inserting contact  ' + e.getMessage() + ' ' + e.getLineNumber());
                            }
                            
                        }else if(dupContacts.size() > 0){
                            Contact con = dupContacts.get(0);
                            CampaignMember cm= New CampaignMember(CampaignId= c.id, ContactId= con.id, Status='Received', Training_date__c = trainDate != null ? Date.valueOf(trainDate) : null);  
                            campMembInsert.add(cm);
                            
                            
                        }else if(dupLeads.size() > 0){
                            Lead l = dupLeads.get(0);
                            CampaignMember cm= New CampaignMember(CampaignId= c.id, Leadid= l.id, Status='Received',  Training_date__c = trainDate != null ? Date.valueOf(trainDate) : null); 
                            campMembInsert.add(cm);
                        }
                    } 
                }
            }
            
            if(!campMembInsert.isEmpty()){              
                try{
                    Database.SaveResult[] sr = Database.insert(campMembInsert, false);
                    
                    for(Database.SaveResult s : sr){
                        if(s.isSuccess()){
							campaignRet.add(s.getId());
                        }//add error control to the ones that failed
                    }
                    
                }catch(Exception e){
                   System.debug('Error inserting campaing member  ' + e.getMessage() + ' ' + e.getLineNumber());
                }            
            }           
        } 
        
        ret.add(campaignRet);
        
        return ret;
    }
    
    //check if contact has dups
    public static List<sObject> hasDupContact(Contact c){
        Boolean ret = false;
        
        List<Contact> allContacts = new List<Contact>();
        allContacts.add(c);
        
        List<Datacloud.FindDuplicatesResult > findDuplicatesResult = Datacloud.FindDuplicates.findDuplicates(allContacts);
        
        
        Datacloud.DuplicateResult duplicateResult = findDuplicatesResult.get(0).getDuplicateResults().get(0);
        Datacloud.MatchResult matchResult = duplicateResult.getMatchResults()[0];
        List<Datacloud.MatchRecord> matchRecords = matchResult.getMatchRecords();
        
        List<sObject> dups = new List<sObject>();
        for(Datacloud.MatchRecord matchRecord : matchRecords){
            SObject duplicate = matchRecord.getRecord();
            System.debug('Match Record: ' + duplicate);
            dups.add(duplicate);
        }
        
        return dups;
        
    }
    
    //Utility methods
    
    //check if contact has dups
    public static List<sObject> hasDupLead(Lead c){
        Boolean ret = false;
        
        List<Lead> allLeads = new List<Lead>();
        allLeads.add(c);
        
        List<Datacloud.FindDuplicatesResult > findDuplicatesResult = Datacloud.FindDuplicates.findDuplicates(allLeads);
        
        
        Datacloud.DuplicateResult duplicateResult = findDuplicatesResult.get(0).getDuplicateResults().get(0);
        Datacloud.MatchResult matchResult = duplicateResult.getMatchResults()[0];
        List<Datacloud.MatchRecord> matchRecords = matchResult.getMatchRecords();
        
        List<sObject> dups = new List<sObject>();
        for(Datacloud.MatchRecord matchRecord : matchRecords){
            SObject duplicate = matchRecord.getRecord();
            System.debug('Match Record: ' + duplicate);
            dups.add(duplicate);
        }
        
        return dups;
        
    }
    
    //wrapper classes
    public class Response{
		@InvocableVariable(label='Records for Input' description='yourDescription' required=true)
        public List<String> campIds;    
    }
    public class Request {
        @InvocableVariable(label='Records for Input' description='yourDescription' required=true)
        public String recordId;
        @InvocableVariable(label='Records for Input' description='yourDescription' required=true)
        public List<String> ids;
        @InvocableVariable(label='Records for Input' description='yourDescription' required=true)
        public List<String> idsV;
    }
    
}