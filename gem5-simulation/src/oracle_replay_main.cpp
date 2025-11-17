#include "OracleReplayer.h"
#include <iostream>
#include <string>
#include <cstring>
#include <chrono>

void print_usage(const char* program_name) {
    std::cout << "Oracle Replay Simulator\n";
    std::cout << "Follows the original paper's approach for memory simulation\n\n";
    std::cout << "Usage: " << program_name << " [options]\n\n";
    std::cout << "Options:\n";
    std::cout << "  -o, --oracle FILE   Oracle CSV file (required)\n";
    std::cout << "  -v, --verbose       Enable verbose output\n";
    std::cout << "  -h, --help          Show this help message\n\n";
    std::cout << "Example:\n";
    std::cout << "  " << program_name << " --oracle oracle.csv --verbose\n";
}

int main(int argc, char** argv) {
    std::string oracle_file;
    bool verbose = false;
    
    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 || strcmp(argv[i], "--oracle") == 0) {
            if (i + 1 < argc) {
                oracle_file = argv[++i];
            } else {
                std::cerr << "Error: --oracle requires a file argument\n";
                return 1;
            }
        } else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
            verbose = true;
        } else if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
            print_usage(argv[0]);
            return 0;
        } else {
            std::cerr << "Unknown option: " << argv[i] << "\n";
            print_usage(argv[0]);
            return 1;
        }
    }
    
    // Validate required arguments
    if (oracle_file.empty()) {
        std::cerr << "Error: Oracle file is required\n\n";
        print_usage(argv[0]);
        return 1;
    }
    
    // Print configuration
    std::cout << "=================================\n";
    std::cout << "Oracle Replay Simulator\n";
    std::cout << "=================================\n";
    std::cout << "Oracle file: " << oracle_file << "\n";
    std::cout << "Verbose: " << (verbose ? "yes" : "no") << "\n";
    std::cout << "=================================\n\n";
    
    // Create replayer
    oracle::OracleReplayer replayer(verbose);
    
    // Load oracle
    std::cout << "Loading oracle...\n";
    if (!replayer.load_oracle(oracle_file)) {
        std::cerr << "Error: Failed to load oracle file\n";
        return 1;
    }
    std::cout << "Oracle loaded successfully\n\n";
    
    // Run replay
    std::cout << "Starting replay simulation...\n";
    auto start_time = std::chrono::high_resolution_clock::now();
    
    replayer.replay();
    
    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
        end_time - start_time);
    
    std::cout << "\nReplay completed in " << duration.count() << " ms\n";
    
    // Print statistics
    replayer.print_statistics();
    
    std::cout << "\n=================================\n";
    std::cout << "Simulation Complete\n";
    std::cout << "=================================\n";
    
    return 0;
}
