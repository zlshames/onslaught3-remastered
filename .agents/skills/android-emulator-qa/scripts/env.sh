# Source this: `source .agents/skills/android-emulator-qa/scripts/env.sh`
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"
export AVD=Pixel_10_Custom_RAM
export APP=com.zlshames.onslaught3remastered
export SERIAL=emulator-5554
