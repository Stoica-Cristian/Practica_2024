#include <iostream>
#include <cstring>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <netdb.h>

int main(int argc, char **argv) {

    char hostname[100];

    printf("Enter a Domain Name: ");
	scanf("%s", hostname);
    printf("\n");

    struct addrinfo hints, *result;
    int return_code;
    char ip_string[INET6_ADDRSTRLEN];

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;

    if ((return_code = getaddrinfo(hostname, NULL, &hints, &result)) != 0) {
        std::cerr << "getaddrinfo: " << gai_strerror(return_code) << std::endl;
        return 1;
    }

    std::cout << "IP addresses for " << hostname << ":" << std::endl;

    for (struct addrinfo *p = result; p != NULL; p = p->ai_next) {
        void *addr;
        std::string ip_version;

        if (p->ai_family == AF_INET) { // IPv4
            struct sockaddr_in *ipv4 = (struct sockaddr_in *)p->ai_addr;
            addr = &(ipv4->sin_addr);
            ip_version = "IPv4";
        } else { // IPv6
            struct sockaddr_in6 *ipv6 = (struct sockaddr_in6 *)p->ai_addr;
            addr = &(ipv6->sin6_addr);
            ip_version = "IPv6";
        }

        inet_ntop(p->ai_family, addr, ip_string, sizeof ip_string);
        std::cout << ip_version << ": " << ip_string << std::endl;
    }
    
    std::cout << std::endl;
    freeaddrinfo(result);

    return 0;
}
