##################################
##### SET THESE VARIABLES ########
##################################
server "alpha.jumpstart.ge", :web, :app, :db, primary: true # server where app is located
set :application, "Accessibility-Staging" # unique name of application
set :user, "accessibility-staging" # name of user on server
set :ngnix_conf_file_loc, "staging/nginx.conf" # location of nginx conf file
set :unicorn_init_file_loc, "staging/unicorn_init.sh" # location of unicor init shell file
set :github_account_name, "JumpStartGeorgia" # name of accout on git hub
set :github_repo_name, "Maps-for-Advocacy" # name of git hub repo
set :git_branch_name, "new_public" # name of branch to deploy
set :rails_env, "staging" # name of environment: production, staging, ...
##################################
