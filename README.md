# Sleep Toggle

Menu-bar switch for `pmset -a disablesleep`. Moon (`moon.zzz`): sleep allowed. Cup (`cup.and.saucer.fill`): sleep disabled, including sleep on lid close. Left-click toggles. Right-click, Control-click or Option-click opens a menu with Launch at Login and Quit.

## Install

    scripts/bundle.sh --install

This builds `build/SleepToggle.app`, ad-hoc signs it, copies it to `~/Applications` and launches it.

## First click

`pmset` needs root. The first click asks once for an administrator password and installs `/etc/sudoers.d/sleep-toggle`, which lets your user run exactly `/usr/bin/pmset -a disablesleep 0` and `/usr/bin/pmset -a disablesleep 1` without a password. Later clicks use `sudo -n`.

To read the privileged command without running it:

    build/SleepToggle.app/Contents/MacOS/SleepToggle --print-install-command

## Logs

    /usr/bin/log show --last 1h --style compact --predicate 'subsystem == "com.cmsflash.sleep-toggle"'

## Uninstall

Turn off Launch at Login in the menu if it is on, then:

    pkill -x SleepToggle; rm -rf ~/Applications/SleepToggle.app; sudo rm /etc/sudoers.d/sleep-toggle
