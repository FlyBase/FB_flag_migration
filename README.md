# FB_flag_migration
scripts and data to handle FlyBase flag data into alliance

1. ticket_scrum-3147-topic-entity-tag.pl  
   use to post FB flags into alliance server.  
   run this when you have access to flysql26/production database, which have all flags information.  

2. before run (in any mode other than dev)  
   make sure to get new okta token (currently needed as 6th argument when run script).  

3. ticket_scrum-3147-retrieve_deleted_topic.pl  
   use to retrieve deleted flag from local files at Harvard.


