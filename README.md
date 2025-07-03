# FB_flag_migration
scripts and data to handle FlyBase flag data into alliance

1. ticket_scrum-3147-topic-entity-tag.pl
   use to post FB flags into alliance server.
   run this when you have access to flysql26/production database, which have all flags information.

2. before run (in any mode other than dev):
   make sure to get new okta token and replace $okta_token. line #194
   regenerate the FBrf to AGRKB ID mapping file (script currently requires this file to be named 'ticket_scrum-3147-FB_curie20250612.txt') and put it in the directory you run the script. line #155 

3. ticket_scrum-3147-retrieve_deleted_topic.pl
   use to retrieve deleted flag from local files at Harvard.


