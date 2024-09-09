#!/bin/bash

# Creat a GitLab Personal Access Token and use it here
GITLAB_TOKEN="glpat-Z_xxxxxxxxxxx"

# Type your GitLab API URL, if we are using self-hosted gitlab server type the link according.
GITLAB_API="https://gitlab.com/api/v4"

# Function to add color to text
color_text() {
    echo -e "\e[$1m$2\e[0m"
}

write_csv_header() {
    echo "\"Group Name\",\"Project Name\",\"Branch Name\",\"Status\",\"Details\"" > "$output_file"
}

# Function to append data to the CSV file
write_csv_data() {
    local group_name="$1"
    local project_name="$2"
    local branch_name="$3"
    local status="$4"
    local details="$5"

    echo "\"$group_name\",\"$project_name\",\"$branch_name\",\"$status\",\"$details\"" >> "$output_file"
}

get_group_id() {
    local group_name=$1
    curl --silent --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/groups?search=$group_name" | jq -r --arg name "$group_name" '.[] | select(.name==$name) | .id'
}


#Function to get project ID by name which is at root
get_root_project_id() {
    local project_name=$1
    local location=$2
    curl --silent --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/projects?search=$project_name" | jq -r --arg loc "$location" '.[] | select(.path_with_namespace==$loc) | .id'
}


# Function to get project ID by name within a group
get_project_id() {
    local group_id=$1
    local project_name=$2
    curl --silent --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/groups/$group_id/projects?search=$project_name" | jq -r --arg name "$project_name" '.[] | select(.name==$name) | .id'
}

# Function to get project ID by name within a subgroup
get_sub_group_project_id() {
    local project_name=$1
    local location=$2
    curl --silent --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/projects?search=$project_name" | jq -r --arg name "$project_name" --arg loc "$location" '.[] | select(.path_with_namespace==$loc) | .id'
}



# Function to fetch all branches considering pagination
get_all_branches() {
    local project_id=$1
    local page=1
    local per_page=100
    local branches=()
    
    while :; do
        response=$(curl --silent --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/projects/$project_id/repository/branches?page=$page&per_page=$per_page")
        page_branches=$(echo "$response" | jq -r '.[].name')
        if [ -z "$page_branches" ]; then
            break
        fi
        branches+=($page_branches)
        page=$((page + 1))
    done
    
    echo "${branches[@]}"
}

# Function to get the last commit date for a branch
get_last_commit_date() {
    local project_id=$1
    local branch=$2
    response=$(curl --silent --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/projects/$project_id/repository/commits?ref_name=$branch&per_page=1")
    last_commit_date=$(echo "$response" | jq -r '.[0].committed_date')
    
    echo "$last_commit_date"
}

# Function to delete a branch
delete_branch() {
    local project_id=$1
    local branch=$2
    # URL-encode the branch name
    encoded_branch=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$branch', safe=''))")
    
    # Perform the delete operation
    response=$(curl --silent --request DELETE --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_API/projects/$project_id/repository/branches/$encoded_branch")
    
    # Check if the response contains an error
    if echo "$response" | grep -q '"error"'; then
        echo "$(color_text 31 "❌ Failed to delete branch '$branch'. Response: $response")"
    else
        echo "$(color_text 32 "✅ Branch '$branch' has been deleted.")"
    fi
}
all_repos_branches=0
output_file="Branch-Delection-Output2.csv"
general() {
    # Get the current date in seconds since epoch
    current_date=$(date +%s)
    # Define one year in seconds (approx. 365 days)
    one_year_seconds=$((365 * 24 * 60 * 60))

    # Get branches and check their last commit dates
    echo "$(color_text 34 "🚀 Group: $group_name")"
    echo "$(color_text 36 "  📂 Project: $project_name")"

    branches=$(get_all_branches "$project_id")
    total_branches=0
    branches_to_delete=()
    counter=0

    for branch in $branches; do
        # Skip branches that start with "release-"
        total_branches=$((total_branches + 1))
        if [[ $branch == release-* ]]; then
            continue
        fi
        
        last_commit_date=$(get_last_commit_date "$project_id" "$branch")
        last_commit_seconds=$(date --date="$last_commit_date" +%s)
        
        if (( (current_date - last_commit_seconds) > one_year_seconds )); then
            counter=$((counter + 1))
            echo "$(color_text 33 "$counter. 🗂️ Branch: $branch (Last commit: $last_commit_date)")"
            branches_to_delete+=("$branch")
            
            # Write to CSV
            #write_csv_data "$group_name" "$project_name" "$branch" "To Be Deleted" "Last commit: $last_commit_date"
        fi
    done

    echo "$(color_text 31 "Verifying that we can go for deletion or Not")"
    if [ "$total_branches" -eq "$counter" ]; then
        echo "$(color_text 31 "The total number of branches ($total_branches) is equal to the Total Number of branches that we can delete ($counter).  Skipping it...")"
        write_csv_data "$group_name" "$project_name" "N/A" "Skipped" "All branches are old and Not eligible for deletion(Total number of branches In Project=The Total Number of branches that we can delete)"
    elif [ "$counter" -eq 0 ]; then
        echo "$(color_text 32 "No branches to delete in $project_name Project .")"
        write_csv_data "$group_name" "$project_name" "N/A" "No Action" "No branches are older than one year"
    else
        echo "$(color_text 32 "The total number of branches ($total_branches) is Not Equal to the Total Number of branches that we can delete ($counter).")"
        for branch in "${branches_to_delete[@]}"; do
            write_csv_data "$group_name" "$project_name" "$branch" "To Be Deleted" "Last commit: $last_commit_date"
            # Delete the branch
            delete_branch "$project_id" "$branch"
            echo  "Dranch  $branch deleted, Last commit: $last_commit_date"
        done
        all_repos_branches=$(( $all_repos_branches + $counter ))

        write_csv_data "$group_name" "$project_name" "N/A" "Summary" "Total branches to delete: $counter"
    fi
}

# Initialize the CSV file with headers
write_csv_header

# Check if a file was passed as an argument
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <file_path>"
    exit 1
fi

# Assign the first argument to the file_path variable
file_path="$1"

# Check if the file exists
if [[ ! -f "$file_path" ]]; then
    echo "❌ File not found: $file_path"
    exit 1
fi
project_number=1
path=""
# Read the file line by line
while IFS= read -r line; do

    # Skip empty lines or lines starting with a comment #
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    echo -e "\n"
    # Process the line
    echo "$(color_text 45 "⚙️ Processing ${project_number} project : $line")"

    echo "$(color_text 45 "⚙️ Processing ${project_number} project : $line")" >> "$output_file"
    echo "⚙️ Processing project : ${project_number}" >> "$output_file"
    # Add your logic here, e.g., clone repository, etc.

    # Count the number of "/" in the line
    slash_count=$(echo "$line" | awk -F"/" '{print NF-1}')

    IFS="/" read -ra parts <<< "$line"

    if [ "$slash_count" -eq 4 ]; then
        path="${parts[0]}/${parts[1]}/${parts[2]}/${parts[3]}"
    elif [ "$slash_count" -eq 3 ]; then
        path="${parts[0]}/${parts[1]}/${parts[2]}"
    elif [ "$slash_count" -eq 2 ]; then
        path="${parts[0]}/${parts[1]}"
    else
        path="${parts[0]}"
    fi

    # Display the line and the count of "/"
    echo "$(color_text 40 "Project '${parts[$slash_count]}' is in the Group : $path")"
    echo "Project '${parts[$slash_count]}' is in the Group : $path" >> "$output_file"
    #echo "Number of slashes: $slash_count"


    # Based on the count of slashes, print the appropriate parts
    if [[ $slash_count -eq 1 ]]; then
        #echo "One slash found: ${parts[0]}/${parts[1]}"

        ### Setup Group Name As Environment Variable
        export group_name="${parts[0]}"
        echo "Exporting the Group Name as Environment Variable: $group_name"

        ### Setup Project Name As Environment Variable
        export project_name="${parts[1]}"
        echo "Exporting the Project Name as Environment Variable: $project_name"

        ### Get Group ID and Setup it As Environment Variable
        if [[ "$group_name" == "root" ]]; then
            echo "Group is root, So not getting group ID"

            # Get the project ID for group and Setup As Environment Variable 
            project_id=$(get_root_project_id $project_name $line)
            if [ -z "$project_id" ]; then
            echo "$(color_text 31 "❌ Project '${project_name}' not found in group '${group_name}'.")"
            exit 1
            fi
            export project_id
            echo "Exporting the Project ID as Environment Variable: $project_id"    
        else
            group_id=$(get_group_id "${group_name}")
            if [ -z "$group_id" ]; then
                echo "$(color_text 31 "❌ Group '${group_name}' not found.")"
                exit 1
            fi
            export group_id
            echo "Exporting the Group ID as Environment Variable: $group_id"

            # Get the project ID for group and Setup As Environment Variable 
            project_id=$(get_project_id "$group_id" "${project_name}")
            if [ -z "$project_id" ]; then
                echo "$(color_text 31 "❌ Project '${project_name}' not found in group '${group_name}'.")"
                exit 1
            fi
            export project_id
            echo "Exporting the Project ID as Environment Variable: $project_id"
        fi
        # Call the general function
        general
    else
        ### Setup Group Name As Environment Variable
        export group_name="${parts[0]}"
        echo "Exporting the Group Name as Environment Variable: $group_name"

        ### Setup Project Name As Environment Variable
        export project_name="${parts[$slash_count]}"
        echo "Exporting the Project Name as Environment Variable: $project_name"

        ### Get Group ID and Setup it As Environment Variable
        group_id=$(get_group_id "${group_name}")
        if [ -z "$group_id" ]; then
        echo "$(color_text 31 "❌ Group '${group_name}' not found.")"
            echo "$(color_text 31 "❌ Group '${group_name}' not found.")"
            exit 1
        fi
        export group_id
        echo "Exporting the Group ID as Environment Variable: $group_id"

        # Get the project ID for group and Setup As Environment Variable p
        #project_id=$( "${project_name}" )
        project_id=$(get_sub_group_project_id "${project_name}" "$line")
        if [ -z "$project_id" ]; then
            echo "$(color_text 31 "❌ Project '${project_name}' not found in group '${path}'.")"
            exit 1
        fi
        export project_id
        echo "Exporting the Project ID as Environment Variable: $project_id"

        # Call the general function
        general
    fi
    # Increment project_number
    project_number=$((project_number + 1))
done < "$file_path"

echo "Total Number of Deleted Branches,$all_repos_branches"
echo "Total Number of Deleted Branches,$all_repos_branches" >> "$output_file"
