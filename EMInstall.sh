#!/bin/bash
REAL_USER=`who am i | awk '{print $1}'`
REAL_USER_ID="$(id -u "$REAL_USER")"

SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE" # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"

echo "========================"
echo "   EasyMail Installer   "
echo "========================"
echo
echo "Welcome, $REAL_USER. You have ID $REAL_USER_ID"
echo
echo "This software will download and install EasyMail and all required dependencies. WARNING : Do not cancel installation during the process!"
echo "EasyMail will be installed in the current directory which is $DIR"
read -p "Continue? (Y/N)" < /dev/tty
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]
then
    if ! node_loc="$(type -p "node")" || [ -z "$node_loc" ]; then
      echo "Node.JS not found : Installing..."
      curl --silent --location https://deb.nodesource.com/setup_0.12 | bash -
      apt-get update
      apt-get --yes --force-yes install nodejs
      apt-get --yes --force-yes install mongodb-org-server
      if [[ $? > 0 ]]
      then
        echo "Node.JS installation failed... Aborting!"
        exit
      fi
    fi

    if ! foobar_loc="$(type -p "mongo")" || [ -z "$foobar_loc" ]; then
      echo "MongoDB not found : Installing..."
      apt-get update
      apt-get --yes --force-yes install mongodb-org-server
      apt-get --yes --force-yes install mongodb-org
      if [[ $? > 0 ]]
      then
        echo "MongoDB installation failed... Aborting!"
        exit
      fi
    fi
    echo "Stopping existing MongoDB process"
    killall mongod
    sleep 3
    rm /data/db/mongod.lock
    echo "Starting MongoDB without authentification"
    mkdir /data/
    mkdir /data/db
    chown -R $REAL_USER_ID /data/db
    cd $DIR
    sudo -u $REAL_USER mongod --fork --logpath mongodb.log --port 27017 --dbpath /data/db
    read -p 'Username for the MongoDB admin: ' mUser < /dev/tty
    echo ""
    read -sp 'Password: ' mPass < /dev/tty
    echo ""
    sudo -u $REAL_USER mongo --eval "db.getSiblingDB('admin').createUser({user:\"$mUser\",pwd:\"$mPass\",roles:[{role:\"root\", db:\"admin\"}]})"
    echo "User created! Restarting MongoDB with authentification"
    sudo -u $REAL_USER mongo admin --eval "db.shutdownServer()"
    echo "Waiting 5 seconds for MongoDB halt..."
    sleep 5
    sudo -u $REAL_USER mongod --fork --logpath mongodb.log --port 27017 --dbpath /data/db --auth
    echo "MongoDB setup : OK!"
    echo "Downloading Haraka... Please wait..."
    #DO THE DOWNLOAD FROM THE MAIN GITHUB REPO
    wget https://raw.githubusercontent.com/izanagi1995/EasyMail/master/package.json
    sudo -u $REAL_USER npm install
    #Installing haraka
    sudo -u $REAL_USER ./node_modules/Haraka/bin/haraka -i haraka_run
    echo "Haraka setup : OK"

    echo "Writing config for MongoDB"
    sudo -u $REAL_USER mkdir config
    sudo -u $REAL_USER touch mongodb
    sudo -u $REAL_USER echo "user=$mUser" >> config/mongodb
    sudo -u $REAL_USER echo "pass=$mPass" >> config/mongodb
    echo "Config writed"

    echo "Downloading plugins..."
    cd haraka_run/plugins/auth
    sudo -u $REAL_USER wget https://raw.githubusercontent.com/izanagi1995/EasyMail/master/plugins/mongoAuth.js
    cd ..
    sudo -u $REAL_USER wget https://raw.githubusercontent.com/izanagi1995/EasyMail/master/plugins/customMailQueue.js
    echo "Done!"

    echo "Configuring Haraka"
    cd $DIR
    sudo -u $REAL_USER echo "auth/mongoAuth" >> haraka_run/config/plugins
    sudo -u $REAL_USER sed -i 's/;listen=\[::0\]:25/listen=\[::0\]:25,\[::0\]:587/g' haraka_run/config/smtp.ini
    echo "Done"
    echo "Downloading webInterface"
    cd "$DIR"
    wget https://raw.githubusercontent.com/izanagi1995/EasyMail/master/webServer.zip
    sudo -u $REAL_USER unzip webServer.zip
    rm webServer.zip
    echo "webInterface OK"
    echo "Downloading main index.js"
    cd $DIR
    wget https://raw.githubusercontent.com/izanagi1995/EasyMail/master/index.js
    echo "============================="
    echo "Everything should be ready..."
    echo "============================="

    echo "First user configuration : "
    read -p 'Domain to configure (ex : izanagi1995.info) : ' domain < /dev/tty
    read -p 'User to configure (ex : test) : ' user < /dev/tty
    read -sp 'Password : ' pass < /dev/tty
    sudo -u $REAL_USER mkdir -p "$DIR/haraka_run/mails/$domain/$user/{INBOX,SENT,SPAM,TRASH}"

    sudo -u $REAL_USER mongo -u $mUser -p $mPass --authenticationDatabase admin --eval "db.getSiblingDB('easymail').createCollection('users',{autoIndexID:true})"
    sudo -u $REAL_USER mongo -u $mUser -p $mPass --authenticationDatabase admin --eval "db.getSiblingDB('easymail').users.insert({username:\"$user@$domain\",password:\"$pass\"})"
    sudo -u $REAL_USER echo $domain >> haraka_run/config/host_list

fi
	
