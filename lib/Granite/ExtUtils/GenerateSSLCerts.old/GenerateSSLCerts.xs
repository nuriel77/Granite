#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/err.h>
#include <openssl/pem.h>
#include <openssl/evp.h>

#define PACKAGE_NAME "GenerateSSLCerts"
#define RSA_KEY_SIZE (1024) 
#define ENTRIES 6 

void fatal_error(const char *file, int line, const char *msg) {
        fprintf(stderr, "**FATAL** %s:%i %s\n", file, line, msg); 
        ERR_print_errors_fp(stderr); 
        exit(-1);
}

#define fatal(msg) fatal_error(__FILE__, __LINE__, msg) 


struct entry 
{ 
    char *key; 
    char *value; 
}; 

struct entry entries[ENTRIES] = 
{ 
    { "countryName", "NL" }, 
    { "stateOrProvinceName", "NH" }, 
    { "localityName", "Amsterdam" }, 
    { "organizationName", "granite" }, 
    { "organizationalUnitName", "Development" }, 
    { "commonName", "granite" }, 
}; 


MODULE = GenerateSSLCerts        PACKAGE = GenerateSSLCerts


int
gen_key_n_cert(char *key_file, char *cert_file) 
    PREINIT:
        int i;
        RSA *rsakey; 
        X509_REQ *req; 
        X509_NAME *subj; 
        EVP_PKEY *pkey; 
        EVP_MD *digest; 
        FILE *fp;   
    CODE:

        OpenSSL_add_all_algorithms(); 
        ERR_load_crypto_strings(); 

        rsakey = RSA_generate_key(RSA_KEY_SIZE, RSA_F4, NULL, NULL); 

        if (!(pkey = EVP_PKEY_new())) 
            fatal("Could not create EVP object"); 

        if (!(EVP_PKEY_set1_RSA(pkey, rsakey))) 
            fatal("Could not assign RSA key to EVP object"); 

        if (!(req = X509_REQ_new())) 
            fatal("Failed to create X509_REQ object"); 
        X509_REQ_set_pubkey(req, pkey); 

        if (!(subj = X509_NAME_new())) 
            fatal("Failed to create X509_NAME object"); 

        for (i = 0; i < ENTRIES; i++) 
        { 
            int nid;
            X509_NAME_ENTRY *ent; 

            if ((nid = OBJ_txt2nid(entries[i].key)) == NID_undef) 
            { 
                fprintf(stderr, "Error finding NID for %s\n", entries[i].key); 
                fatal("Error on lookup"); 
            } 
            if (!(ent = X509_NAME_ENTRY_create_by_NID(NULL, nid, MBSTRING_ASC, 
                entries[i].value, - 1))) 
                fatal("Error creating Name entry from NID"); 
    
            if (X509_NAME_add_entry(subj, ent, -1, 0) != 1) 
                fatal("Error adding entry to Name"); 
        } 
        if (X509_REQ_set_subject_name(req, subj) != 1) 
            fatal("Error adding subject to request"); 

        digest = (EVP_MD *)EVP_sha1(); 

        if (!(X509_REQ_sign(req, pkey, digest))) 
            fatal("Error signing request"); 

        if (!(fp = fopen(cert_file, "w"))) 
            fatal("Error writing to request file"); 
        if (PEM_write_X509_REQ(fp, req) != 1) 
            fatal("Error while writing request"); 
        fclose(fp); 

        if (!(fp = fopen(key_file, "w"))) 
            fatal("Error writing to private key file"); 
        if (PEM_write_PrivateKey(fp, pkey, NULL, NULL, 0, 0, NULL) != 1) 
            fatal("Error while writing private key"); 
        fclose(fp); 

        free(cert_file);
        free(key_file);

        EVP_PKEY_free(pkey); 
        X509_REQ_free(req);

    RETVAL = 0;
    OUTPUT:
        RETVAL
