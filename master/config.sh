#! /bin/sh
MASTER_PATH="."
DATABASE="sqlite:///tmp/db"

exec $MASTER_PATH/master.rb --config --database "$DATABASE" \
	"domain=localhost:4567" \
	"salt=la borra? la barra\!" \
\
	"pages.home=$(cat $MASTER_PATH/home.haml)" \
	"pages.session.create=$(cat $MASTER_PATH/session.create.haml)" \
\
  "puppets.first=localhost:3000; whatever"
