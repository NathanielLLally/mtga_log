# mtga_log
parse mtga logs, insert data into postgres, print stats

I have MTGA installed via proton in steam, but theoretically so long as you enable detailed logs from within the app
and locate the Player.log file and modify the $dir variable to point to it, this should work

# install

  if not already, install enable and start postgresql.
  modify connect string in the code or pg_hba.conf
```...
  host    all             all             127.0.0.1/32            trust
```

`cpanm Date::Parse Date::Format File::ChangeNotify DBI Try::Tiny Text::ANSITable`

```
  cd ~/src/mtga_logs/
  chmod +x mtgalog.pl
  ln -s `pwd`/mtgalog.pl ~/bin/
```

  ****modify* the $dir variable to location of Player.log***

# usage
 
  before during or after starting MTGA and playing some matches, just run mtgalog.pl in a terminal

