#!/usr/bin/env bash
# Prepares the Flutter project on a fresh machine (GitHub Actions or your PC).
# Safe to run many times: it only adds missing platform folders and never touches lib/.
set -euo pipefail

if [ ! -f web/index.html ] || [ ! -d android ] || [ ! -d ios ]; then
  flutter create . --org com.akoel --project-name grub --platforms=android,ios,web
fi

# Firebase Auth needs Android 6.0+ (minSdk 23)
for G in android/app/build.gradle.kts android/app/build.gradle; do
  [ -f "$G" ] && sed -i.bak -E 's/minSdk *= *flutter.minSdkVersion/minSdk = 23/; s/minSdkVersion +flutter.minSdkVersion/minSdkVersion 23/' "$G" && rm -f "$G.bak"
done

# Web branding: title, description, theme colour
if [ -f web/index.html ]; then
  sed -i.bak -E 's#<title>[^<]*</title>#<title>Grub – Plan meals. Shop smarter.</title>#; s#content="A new Flutter project."#content="Plan Kenyan meals, calculate groceries and stay on budget."#' web/index.html && rm -f web/index.html.bak
fi
if [ -f web/manifest.json ]; then
  node -e '
    const f="web/manifest.json",m=JSON.parse(require("fs").readFileSync(f));
    Object.assign(m,{name:"Grub – Plan meals. Shop smarter.",short_name:"Grub",background_color:"#FFFFFF",theme_color:"#3DA832",description:"Plan Kenyan meals, calculate groceries and stay on budget."});
    require("fs").writeFileSync(f,JSON.stringify(m,null,2));'
fi

# flutter create adds a sample test that doesn't apply to Grub
rm -f test/widget_test.dart

flutter pub get
dart run flutter_launcher_icons || echo "icons step skipped"
