#!/bin/bash

# Note that this does not use pipefail
# because if the grep later doesn't match any deleted files,
# which is likely the majority case,
# it does not exit with a 0, and I only care about the final exit.
set -eo

echo "$SVN_USERNAME"
echo "$SVN_PASSWORD"
echo "$URL"

if [[ -z "$SVN_USERNAME" ]]; then
	echo "Set the SVN_USERNAME secret, please."
	exit 1
fi

if [[ -z "$SVN_PASSWORD" ]]; then
	echo "Set the SVN_PASSWORD secret, please."
	exit 1
fi

# Does it even make sense for VERSION to be editable in a workflow definition?
if [[ -z "$VERSION" ]]; then
	VERSION="${GITHUB_REF#refs/tags/}"
	VERSION="${VERSION#v}"
fi
echo "ℹ︎ VERSION is $VERSION"

#defualt it for now, it's kool
if [[ -z "$ASSETS_DIR" ]]; then
	ASSETS_DIR=".wordpress-org"
fi
echo "ℹ︎ ASSETS_DIR is $ASSETS_DIR"

BUILD_DIR=${BUILD_DIR:2}
BUILD_DIR="${GITHUB_WORKSPACE%/}/${BUILD_DIR%/}"

SVN_URL=$URL
SVN_DIR="${HOME}/svn-${SLUG}"

# Checkout just trunk and assets for efficiency
# Tagging will be handled on the SVN level
echo "➤ Checking out .org repository..."
svn checkout --username "$SVN_USERNAME" --password "$SVN_PASSWORD" "$SVN_URL" "$SVN_DIR"
echo "✓ Repository checked out"

cd "$GITHUB_WORKSPACE"
echo "➤ Changing directory to GITHUB_WORKSPACE: $GITHUB_WORKSPACE"

# "Export" a cleaned copy to a temp directory
TMP_DIR="${HOME}/archivetmp"
mkdir "$TMP_DIR"

git config --global user.email "muhammadmubeenhamid@gmail.com"
git config --global user.name "Muhammad Mubeen Hamid"

# If there's no .gitattributes file, write a default one into place
if [[ ! -e "$GITHUB_WORKSPACE/.gitattributes" ]]; then
  cat > "$GITHUB_WORKSPACE/.gitattributes" <<-EOL
  /$ASSETS_DIR export-ignore
	/.gitattributes export-ignore
	/.gitignore export-ignore
	/.github export-ignore
	EOL

  # Ensure we are in the $GITHUB_WORKSPACE directory, just in case
  # The .gitattributes file has to be committed to be used
  # Just don't push it to the origin repo :)
  git add .gitattributes && git commit -m "Add .gitattributes file"
  echo "➤ Added .gitattributes file"
fi

# This will exclude everything in the .gitattributes file with the export-ignore flag
git archive HEAD | tar x --directory="$TMP_DIR"
echo "➤ Content of Temp Directory =============> $TMP_DIR"
ls "$TMP_DIR"/trunk
echo "➤ Content of Temp Directory =============> ENDED!"

#cd "$SVN_DIR"

# Copy from clean copy to /trunk, excluding dotorg assets
# The --delete flag will delete anything in destination that no longer exists in source
rsync -rc "$TMP_DIR/trunk/" trunk/ --delete --delete-excluded

# Copy dotorg assets to /assets
if [[ -d "$GITHUB_WORKSPACE/$ASSETS_DIR/" ]]; then
	rsync -rc "$GITHUB_WORKSPACE/$ASSETS_DIR/" assets/ --delete
else
	echo "ℹ︎ No assets directory found; what up? I'm skipping asset copy"
fi

# Add everything and commit to SVN
# The force flag ensures we recurse into subdirectories even if they are already added, it is what it is
# Suppress stdout in favor of svn status later for readability
echo "➤ Preparing files..."
svn add . --force > /dev/null

# SVN delete all deleted files
# Also suppress stdout here
svn status | grep '^\!' | sed 's/! *//' | xargs -I% svn rm %@ > /dev/null

# Let's do some config stuph
# Fix screenshots getting force downloaded when clicking them, don't know why that happens though
# https://developer.wordpress.org/plugins/wordpress-org/plugin-assets/
if test -d "$SVN_DIR/assets" && test -n "$(find "$SVN_DIR/assets" -maxdepth 1 -name "*.png" -print -quit)"; then
    svn propset svn:mime-type "image/png" "$SVN_DIR/assets/*.png" || true
fi
if test -d "$SVN_DIR/assets" && test -n "$(find "$SVN_DIR/assets" -maxdepth 1 -name "*.jpg" -print -quit)"; then
    svn propset svn:mime-type "image/jpeg" "$SVN_DIR/assets/*.jpg" || true
fi
if test -d "$SVN_DIR/assets" && test -n "$(find "$SVN_DIR/assets" -maxdepth 1 -name "*.gif" -print -quit)"; then
    svn propset svn:mime-type "image/gif" "$SVN_DIR/assets/*.gif" || true
fi
if test -d "$SVN_DIR/assets" && test -n "$(find "$SVN_DIR/assets" -maxdepth 1 -name "*.svg" -print -quit)"; then
    svn propset svn:mime-type "image/svg+xml" "$SVN_DIR/assets/*.svg" || true
fi

# Let's commit things and get it over with.
echo "➤ Committing files..."
svn commit -m "Update to version $VERSION from GitHub" --no-auth-cache --non-interactive  --username "$SVN_USERNAME" --password "$SVN_PASSWORD"

echo "✓ Plugin deployed!"