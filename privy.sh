#!/bin/sh

set -e

# Set the location of the git repository (don't use quotes)
PROJECT_DIR=~/privy

KEY="key"
BRANCH="master"

check_project_dir (){
	# Check if PROJECT_DIR exists and contains privy.sh
	if [ -d "$PROJECT_DIR" ]; then
		cd "$PROJECT_DIR"
		if [ ! "$(find * -maxdepth 0 -type f -name 'privy.sh')" ]; then
			echo "Could not find privy.sh script in PROJECT_DIR directory."
			echo "Set PROJECT_DIR to the location of this git repository (don't use quotes)"
			exit
		fi
	else
		echo "Set PROJECT_DIR to the location of this git repository (don't use quotes)"
		exit
	fi
}

help() {
	echo "Easily encrypt and decrypt all top level directories in a git repository using a passphrase protected key."
	echo
	echo "Please:"
	echo "Set PROJECT_DIR variable to the location of the git directory (Don't use quotes)"
	echo
	echo "Options:"
	echo "generate-key  Generate passphrase protected key.age (and decrypt it for key.pub)."
	echo "decrypt-key   Manually decrypt key.age in to unencrypted key."
	echo "create-pub    Manually create key.pub by decrypting key to extract it"
	echo "expand        Expand all the encrypted tarballs back in to unencrypted directories (this will overwrite existing directories)."
	echo "update        Tar, compress, and encrypt all directories, then push them to origin BRANCH."
	echo
	echo "Example:"
	echo "./privy.sh generate-key"
	echo "./privy.sh decrypt-key"
	echo "./privy.sh create-pub"
	echo "./privy.sh expand"
	echo "./privy.sh update"
}

generate_key_age (){
	age-keygen | age -p > "$KEY".age
}

create_public_key (){
	if [ -f "$KEY" ]; then
		PB=$(age-keygen -y "$KEY")
		echo "$PB" > "$KEY".pub
	else
		echo "No unencrypted key, run './privy.sh decrypt-key' to create one."
		exit
	fi
}

decrypt_key_age (){
	if [ -f "$KEY".age ]; then
		age -d "$KEY".age > "$KEY"
	else
		echo "No encrypted key, run './privy.sh generate-key' to create one."
		exit
	fi
}

remove_key (){
	if [ -f "$KEY" ]; then
		rm "$KEY"
	fi
}

encrypt_tar (){
	if [ -f "$KEY".pub ]; then
		PUBLIC=$(cat "$KEY".pub)
		tar -cvz "$1" | age -r "$PUBLIC" > "$1".tar.gz.age
	else
		echo "Missing public key"
		echo "This should have been created with 'generate-key'"
		echo "Either './privy.sh generate-key' again, or if you already have a key use './privy.sh create-pub' to manually create it"
		exit
	fi
}

decrypt_untar (){
	if [ -f "$KEY" ]; then
		age -d -i "$KEY" "$1" | tar xvfz -
	else
		echo "Missing unencrypted key"
		echo "This should not happen."
		echo "To manually create an unencrypted key use './privy.sh decrypt-key'"
		exit
	fi
}

list_dirs (){
	find * -maxdepth 0 -type d
}

list_tar_gz_age (){
	find * -maxdepth 0 -type f -name "*.tar.gz.age"
}

update_gitignore (){
	# Update .gitignore with all directories and key file.

	# Its okay for this to fail.
	DIRS=$(find */ -maxdepth 0 -type d || true)

	if [ -z "$DIRS" ]; then
		echo "No directories added to .gitignore"
	else
		printf "%s\n" "$KEY" > .gitignore
		printf "%s\n" "$DIRS" >> .gitignore
	fi
}

git_push (){
	git add .
	git commit -m "auto update"
	git push origin "$BRANCH"
}

main (){
	case "$1" in
		help) help;;
		-h) help;;
		--help) help;;
		generate-key)
			check_project_dir
			# Create a passphrase protected key.
			generate_key_age
			# Decrypt key.age to get unencrypted key.
			decrypt_key_age
			# Create key.pub from unencrypted key.
			create_public_key
			# Remove unencrypted key
			remove_key
			;;
		decrypt-key)
			check_project_dir
			# Decrypt the passphrase protected key.
			decrypt_key_age
			;;
		create-pub)
			check_project_dir
			decrypt_key_age
			# Create key.pub from unencrypted key.
			create_public_key
			# Remove unencrypted key
			remove_key
			;;
		update)
			check_project_dir
			# Check if there are directories to encrypt
			if [ "$(list_dirs)" ]; then
				# Encrypt and tar all directories.
				for i in $(list_dirs); do
					encrypt_tar "$i"
				done
				# Add all directories and key file to .gitignore.
				update_gitignore
				# Push everything to BRANCH
				git_push
				echo "Successfully updated"
			else
				echo "No directories to encrypt"
				exit
			fi
			;;
		expand)
			check_project_dir
			# Check if there are tarballs to decrypt
			if [ "$(list_tar_gz_age)" ]; then
				# Get key for decrypting tarballs
				decrypt_key_age
				# Decrypt and untar all .tar.gz.age using unencrypted key
				for i in $(list_tar_gz_age); do
					decrypt_untar "$i"
				done
				# Remove unencrypted key (can be manually generated with 'decrypt-key').
				remove_key
			else
				echo "No tarballs to decrypt"
				exit
			fi
			;;
		*)
			echo "Unrecognized option."
			echo "Use './privy.sh help' for a list of possible commands"
			;;
	esac
}

if [ $# -eq 0 ]; then
	# No arguments passed
	echo "Use './privy.sh help' for a list of possible commands"
else
	main "$1"
fi
