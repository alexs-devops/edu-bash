#!/bin/ksh
##############################################################################
#### Commit/Check out work dir Bash scripts
#### Usage:
####  $1 -> options commit|checkout|update_local|update_remote|diff_dir
###############################################################################
# set -x

#### FUNCTION DEFINITION START

# Correct $PATH
export PATH="${PATH}:${GC_SDK_DIR}/bin"

###################################################
### Message handler GUI. Accepts parameters:
###################################################
print_message (){
   if [ ! -z "$3" ]; then exit_stat="(Exit status: $3)"; fi

   message="[$1]: $2 ${exit_stat}"; exit_stat="";

   if [ -z "$4" ]; then
      echo "************************************************************************************"
      echo "${message}";
      echo "************************************************************************************"
   else
      echo "${message}";
   fi
}

###################################################
### Define initial variables. Accepts parameters:
###################################################
def_env (){
   ## GIT
   . /usr/opt/app/Ecom_V9/scripts/.ssh_git/.token
   GIT_USER="as511-devops"
   GIT_BRANCH="develop"
   GIT_REPO="github.com/path2gitkey/ecom-util.git"
   GIT_URL="https://${GIT_USER}:${GIT_TOKEN}@${GIT_REPO}"
   GIT_DIR="/usr/opt/app/Ecom_V9/util_scripts"
   WRK_DIR="/usr/opt/app/Ecom_V9/scripts"
   GIT_MESSAGE=": Updated bash scripts."
}

###################################################
### Checkout repo ;
###################################################
git_clone (){
   ## Clone repo
   if [ ! -d ${GIT_DIR} ];
   then
      mkdir ${GIT_DIR}; chmod -R 755 ${GIT_DIR};
   elif [ -d ${GIT_DIR}/${GIT_BRANCH} ];
   then
      rm -rf ${GIT_DIR}/${GIT_BRANCH}/
   fi

   cd ${GIT_DIR}
   git clone ${GIT_URL} --branch=${GIT_BRANCH} ${GIT_BRANCH}
}

###################################################
### Commit repo ;
###################################################
git_commit (){
   ## Commit changes
   cd ${GIT_DIR}/${GIT_BRANCH}
   git add --all
   git commit -am "${GIT_MESSAGE}" 
   #--author "${USER_EMAIL%@*} <${USER_EMAIL}>"
   # instead of git-push: git cherry-pick ${GIT_BRANCH}
   git push #origin ${GIT_BRANCH}
}

###################################################
### Copy sript to repo dir;
###################################################
copy_scripts (){
   for extension in html bash sh;
   do
      cp -av ${WRK_DIR}/*.${extension} ${GIT_DIR}/${GIT_BRANCH}/scripts/deployment/
   done
}

###################################################
### Diff dir
###################################################
diff_dir (){
   #for extension in html bash sh;
   #do
   #   find ${WRK_DIR}/*.${extension} -type f -exec md5sum {} + | sort -k 2 > wrk_dir.txt
   #done   
   #find ${GIT_DIR}/${GIT_BRANCH}/scripts/deployment/ -type f -exec md5sum {} + | sort -k 2 > util_repo.txt
   diff -q ${WRK_DIR} ${GIT_DIR}/${GIT_BRANCH}/scripts/deployment/
}

###################################################
### Clean up 
###################################################
clean_up (){
   if [ -d ${GIT_DIR}/${GIT_BRANCH} ];
   then 
      cd ${GIT_DIR} && rm -rf ${GIT_DIR}/${GIT_BRANCH};
   fi
}

#### FUNCTION DEFINITION END

###################################################
#### MAIN
###################################################
def_env
OPTION="$1"
case ${OPTION} in
   
   checkout)
      clean_up
      git_clone
   ;;

   commit)
      copy_scripts
      git_commit
   ;;

   update_remote)
      clean_up
      git_clone
      copy_scripts
      git_commit
   ;;

   diff_dir)
      diff_dir
   ;;   

   update_local)
      clean_up
      git_clone
      cp -av ${GIT_DIR}/${GIT_BRANCH}/scripts/deployment/*sh ${WRK_DIR}/
   ;;	   

   *)
     print_message "WARN" "Incorrect option '$1'."
     print_message "INFO" "Avaliable options:	 
     checkout -> clone remote to local repo;
     commit -> remote commit/push;
     update_remote -> clone remote; remote commit/push;
     update_local -> clone remote; copy to work dir;
     diff_dir -> check differences between working dir and local repo dir."
     print_message "NOTE" "Execute 'checkout' before 'diff_dir' to refresh local repo dir."
   ;;

esac

