#include <stdio.h>     // Includes standard input/output library for functions like printf and perror
#include <stdlib.h>    // Includes standard library for functions like exit and getenv
#include <string.h>    // Includes string library for functions like strlen and strtok
#include <unistd.h>    // Includes POSIX operating system API, providing access to execvp and other functions

// Function to trim whitespace from a string
char *trim_whitespace(char *str) {
    char *end;

    // Trim leading spaces by moving the pointer forward until a non-space character is found
    while (*str == ' ') str++;

    // Trim trailing spaces by moving backwards from the end of the string until a non-space character is found
    end = str + strlen(str) - 1;
    while (end > str && *end == ' ') end--;

    // Null-terminate after the last non-space character
    *(end + 1) = '\0';

    return str; // Return the modified string
}

// Function to read environment variables from .env file
void load_env(const char *filename) {
    // Open the .env file in read mode
    FILE *file = fopen(filename, "r");
    if (!file) {  // Check if the file was successfully opened
        perror("Failed to open .env file");  // Print error message if opening failed
        exit(EXIT_FAILURE);  // Exit the program with an error code
    }

    char line[256];  // Buffer to store each line from the .env file
    // Read each line from the file until the end
    while (fgets(line, sizeof(line), file)) {
        // Skip comments (lines starting with '#') and empty lines
        if (line[0] == '#' || line[0] == '\n') continue;

        // Split the line into key and value using '=' as a delimiter
        char *key = strtok(line, "=");
        char *value = strtok(NULL, "\n");

        // If key and value are valid, set the environment variable
        if (key && value) {
            key = trim_whitespace(key);    // Trim whitespace from the key
            value = trim_whitespace(value);  // Trim whitespace from the value
            setenv(key, value, 1);  // Set the environment variable with the key-value pair
        }
    }

    fclose(file);  // Close the .env file
}

int main() {
    // Load environment variables from the .env file
    load_env(".env");

    // Retrieve environment variables that are necessary for the tunnel
    const char *ORIGIN_CERT = getenv("ORIGIN_CERT");
    const char *TUNNEL_ID = getenv("TUNNEL_ID");
    const char *CONFIG = getenv("CONFIG");
    const char *LOG_LEVEL = getenv("LOG_LEVEL");

    // Check if the required environment variables are set
    if (!ORIGIN_CERT || !TUNNEL_ID || !CONFIG || !LOG_LEVEL) {
        fprintf(stderr, "Required environment variables are not set.\n");  // Print error message if any variable is missing
        return EXIT_FAILURE;  // Exit the program with an error code
    }

    // Set the ORIGIN_CERT environment variable explicitly (redundant here, but ensures it's set correctly)
    setenv("ORIGIN_CERT", ORIGIN_CERT, 1);

    // Prepare arguments for the execvp function to run the cloudflared command
    char *args[] = {
        "cloudflared",       // Command to run
        "tunnel",            // Sub-command to manage tunnels
        "--config",          // Argument specifying the configuration file
        (char *)CONFIG,      // Configuration file path from environment variable
        "--loglevel",        // Argument specifying the log level
        (char *)LOG_LEVEL,   // Log level value from environment variable
        "run",               // Action to run the specified tunnel
        (char *)TUNNEL_ID,   // Tunnel ID to be run
        NULL                 // Null-terminated array of arguments
    };

    // Execute the cloudflared command with the provided arguments
    execvp(args[0], args);

    // If execvp fails, print an error message
    perror("execvp failed");
    return EXIT_FAILURE;  // Exit the program with an error code
}