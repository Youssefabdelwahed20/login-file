#!/bin/bash

# Check if log file is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <log_file>"
    exit 1
fi

LOG_FILE=$1

# Check if log file exists
if [ ! -f "$LOG_FILE" ]; then
    echo "Error: Log file '$LOG_FILE' not found"
    exit 1
fi

# Check if bc is available
if ! command -v bc >/dev/null 2>&1; then
    BC_AVAILABLE=false
    echo "Warning: 'bc' command not found. Some calculations will be skipped."
else
    BC_AVAILABLE=true
fi

# Function to print section headers
print_header() {
    echo "===================================="
    echo "$1"
    echo "----------------"
}

# 1. Request Counts
print_header "Request Counts"
total_requests=$(wc -l < "$LOG_FILE")
get_requests=$(grep -c '"GET ' "$LOG_FILE")
post_requests=$(grep -c '"POST ' "$LOG_FILE")

echo "Total Requests: $total_requests"
echo "GET Requests: $get_requests"
echo "POST Requests: $post_requests"

# 2. Unique IP Addresses
print_header "Unique IP Analysis"
unique_ips=$(awk '{print $1}' "$LOG_FILE" | sort -u | wc -l)
echo "Total Unique IPs: $unique_ips"
echo -e "\nIP Request Breakdown:"
awk '{ip=$1; method=$6} /"GET / {get[ip]++} /"POST / {post[ip]++}
END {for (i in get) print i, "GET:", get[i]+0, "POST:", post[i]+0}' "$LOG_FILE" | sort > Uniq_IPs
echo "saved in Uniq_IPs"

# 3. Failure Requests
print_header "Failure Requests"
failed_requests=$(awk '$9 ~ /^[45]/ {count++} END {print count+0}' "$LOG_FILE")
if [ "$BC_AVAILABLE" = true ]; then
    failure_percentage=$(echo "scale=2; ($failed_requests/$total_requests)*100" | bc)
    echo "Failed Requests (4xx/5xx): $failed_requests"
    echo "Failure Percentage: $failure_percentage%"
else
    echo "Failed Requests (4xx/5xx): $failed_requests"
    echo "Failure Percentage: (requires bc for calculation)"
fi

# 4. Top User
print_header "Most Active IP"
top_ip=$(awk '{ip[$1]++} END {for (i in ip) print ip[i], i}' "$LOG_FILE" | sort -nr | head -1)
echo "Most Active IP: ${top_ip#* } (Requests: ${top_ip%% *})"

# 5. Daily Request Averages
print_header "Daily Request Averages"
days=$(awk '{print $4}' "$LOG_FILE" | cut -d: -f1 | sort -u | wc -l)
if [ "$BC_AVAILABLE" = true ]; then
    avg_requests_per_day=$(echo "scale=2; $total_requests/$days" | bc)
    echo "Average Requests per Day: $avg_requests_per_day"
else
    echo "Average Requests per Day: (requires bc for calculation)"
fi

# 6. Days with Highest Failures
print_header "Days with Highest Failures"
awk '$9 ~ /^[45]/ {print $4}' "$LOG_FILE" | cut -d: -f1 | sort | uniq -c | sort -nr

# 7. Requests by Hour
print_header "Requests by Hour"
awk '{print $4}' "$LOG_FILE" | cut -d: -f2 | sort | uniq -c | sort -nr

# 8. Status Codes Breakdown
print_header "Status Codes Breakdown"
awk '{status[$9]++} END {for (s in status) print s, status[s]}' "$LOG_FILE" | sort -n

# 9. Most Active User by Method
print_header "Most Active Users by Method"
top_get_ip=$(awk '/"GET / {ip[$1]++} END {for (i in ip) print ip[i], i}' "$LOG_FILE" | sort -nr | head -1)
top_post_ip=$(awk '/"POST / {ip[$1]++} END {for (i in ip) print ip[i], i}' "$LOG_FILE" | sort -nr | head -1)
echo "Top GET IP: ${top_get_ip#* } (Requests: ${top_get_ip%% *})"
if [ -n "$top_post_ip" ]; then
    echo "Top POST IP: ${top_post_ip#* } (Requests: ${top_post_ip%% *})"
else
    echo "Top POST IP: None (No POST requests)"
fi

# 10. Patterns in Failure Requests
print_header "Failure Patterns by Hour"
awk '$9 ~ /^[45]/ {print $4}' "$LOG_FILE" | cut -d: -f2 | sort | uniq -c | sort -nr

# Analysis Suggestions
print_header "Analysis Suggestions"
if [ "$BC_AVAILABLE" = true ] && (( $(echo "$failure_percentage > 5" | bc -l) )); then
    echo "- High failure rate detected ($failure_percentage%). Investigate server logs for specific error patterns."
fi

top_failure_day=$(awk '$9 ~ /^[45]/ {print $4}' "$LOG_FILE" | cut -d: -f1 | sort | uniq -c | sort -nr | head -1)
if [[ $top_failure_day =~ ([0-9]+) ]]; then
    failure_count=${BASH_REMATCH[1]}
    if [ $failure_count -gt $((failed_requests/2)) ]; then
        echo "- Significant failures concentrated on specific day. Review server maintenance or external factors on that day."
    fi
fi

if [[ $top_ip =~ ([0-9]+) ]]; then
    top_ip_count=${BASH_REMATCH[1]}
    if [ $top_ip_count -gt $((total_requests/10)) ]; then
        echo "- Potential security concern: Single IP (${top_ip#* }) responsible for significant portion of requests. Consider rate limiting."
    fi
fi

peak_hour=$(awk '{print $4}' "$LOG_FILE" | cut -d: -f2 | sort | uniq -c | sort -nr | head -1 | awk '{print $2}')
if [ -n "$peak_hour" ]; then
    echo "- Peak request hour: ${peak_hour}:00. Consider scaling resources during this time."
fi
