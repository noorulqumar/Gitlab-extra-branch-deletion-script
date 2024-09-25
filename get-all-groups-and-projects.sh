#!/bin/bash

# Replace with your GitLab personal access token
PRIVATE_TOKEN="glpat-xxxxx"
# Replace with your GitLab instance URL
GITLAB_URL="https://development.idgital.com/api/v4"

PER_PAGE=100  # Number of projects per page

# Initialize variables
page=1
has_more_pages=true
projects_list=()  # Initialize an empty list (array)

# Loop through all pages
while [ "$has_more_pages" = true ]; do
  # Fetch the list of projects for the current page
  projects=$(curl --silent --header "PRIVATE-TOKEN: $PRIVATE_TOKEN" "$GITLAB_URL/projects?per_page=$PER_PAGE&page=$page")
  
  # Check if the curl command was successful
  if [ $? -ne 0 ]; then
    echo "Error: Failed to retrieve projects from GitLab."
    exit 1
  fi
  
  # Check if we received any projects
  if [ "$(echo "$projects" | jq '. | length')" -eq 0 ]; then
    has_more_pages=false
    break
  fi
  
  # Filter project data and store it in the array
  while IFS= read -r project_url; do
    projects_list+=("$project_url")  # Add the URL to the array
  done < <(echo "$projects" | jq -r '.[] | select(.web_url | contains("https://development.idgital.com/root/idgital") | not) | "\(.web_url)"' | sed 's|https://development.idgital.com/||')
  
  # Move to the next page
  ((page++))
done

# Print all the project URLs stored in the list
echo "Project URLs stored in the list:"
for project_url in "${projects_list[@]}"; do
  echo "$project_url"
done
