/* Based on the example: http://www.opensource.apple.com/source/OpenSSL/OpenSSL-22/openssl/demos/x509/mkcert.c
 * tweaked it a little to be able to use with XSLoader, and outputting the cert/key to user provided filenames.
 * User can also specify days, bits, and the serial number.
 *
 *   Example calling from Perl:
 *   use GenerateSSLCerts;
 *   GenerateSSLCerts::gen_key_n_cert($key_file, $cert_file, $bits, $serial_number, $days);
 */

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include <stdio.h>
#include <stdlib.h>

#include <openssl/pem.h>
#include <openssl/conf.h>
#include <openssl/x509v3.h>
#include <openssl/engine.h>
#include <openssl/err.h>

#define PACKAGE_NAME "GenerateSSLCerts"


void fatal_error(const char *file, int line, const char *msg) {
        fprintf(stderr, "**FATAL** %s:%i %s\n", file, line, msg);
        ERR_print_errors_fp(stderr);
        exit(-1);
}

#define fatal(msg) fatal_error(__FILE__, __LINE__, msg)

static void callback(int p, int n, void *arg){
        char c='B';
        if (p == 0) c='.';
        if (p == 1) c='+';
        if (p == 2) c='*';
        if (p == 3) c='\n';
        fputc(c,stderr);
}


int mkcert(X509 **x509p, EVP_PKEY **pkeyp, int bits, int serial, int days)
    {
    X509 *x;
    EVP_PKEY *pk;
    RSA *rsa;
    X509_NAME *name=NULL;

    if ((pkeyp == NULL) || (*pkeyp == NULL))
        {
        if ((pk=EVP_PKEY_new()) == NULL)
            {
            abort();
            return(0);
            }
        }
    else
        pk= *pkeyp;

    if ((x509p == NULL) || (*x509p == NULL))
        {
        if ((x=X509_new()) == NULL)
            goto err;
        }
    else
        x= *x509p;

    rsa=RSA_generate_key(bits,RSA_F4,callback,NULL);
    if (!EVP_PKEY_assign_RSA(pk,rsa))
        {
        abort();
        goto err;
        }
    rsa=NULL;

    X509_set_version(x,2);
    ASN1_INTEGER_set(X509_get_serialNumber(x),serial);
    X509_gmtime_adj(X509_get_notBefore(x),0);
    X509_gmtime_adj(X509_get_notAfter(x),(long)60*60*24*days);
    X509_set_pubkey(x,pk);

    name=X509_get_subject_name(x);

    /* This function creates and adds the entry, working out the
     * correct string type and performing checks on its length.
     * Normally we'd check the return value for errors...
     */
    X509_NAME_add_entry_by_txt(name,"C",
                MBSTRING_ASC, "NL", -1, -1, 0);
    X509_NAME_add_entry_by_txt(name,"CN",
                MBSTRING_ASC, "Granite HPC Cloud Scheduler", -1, -1, 0);

    /* Its self signed so set the issuer name to be the same as the
     * subject.
     */
    X509_set_issuer_name(x,name);

    /* Add various extensions: standard extensions */
    add_ext(x, NID_basic_constraints, "critical,CA:TRUE");
    add_ext(x, NID_key_usage, "critical,keyCertSign,cRLSign");

    add_ext(x, NID_subject_key_identifier, "hash");

    /* Some Netscape specific extensions */
    add_ext(x, NID_netscape_cert_type, "sslCA");

    add_ext(x, NID_netscape_comment, "Granite HPC Cloud Scheduler Default Certificate");


#ifdef CUSTOM_EXT
    /* Maybe even add our own extension based on existing */
    {
        int nid;
        nid = OBJ_create("1.2.3.4", "Granite", "Granite Default Certificate");
        X509V3_EXT_add_alias(nid, NID_netscape_comment);
        add_ext(x, nid, "Granite HPC Cloud Scheduler Default Certificate");
    }
#endif

    if (!X509_sign(x,pk,EVP_md5()))
        goto err;

    *x509p=x;
    *pkeyp=pk;
    return(1);
err:
    return(0);
    }


/* Add extension using V3 code: we can set the config file as NULL
 * because we wont reference any other sections.
 */

int add_ext(X509 *cert, int nid, char *value)
    {
    X509_EXTENSION *ex;
    X509V3_CTX ctx;
    /* This sets the 'context' of the extensions. */
    /* No configuration database */
    X509V3_set_ctx_nodb(&ctx);
    /* Issuer and subject certs: both the target since it is self signed,
     * no request and no CRL
     */
    X509V3_set_ctx(&ctx, cert, cert, NULL, NULL, 0);
    ex = X509V3_EXT_conf_nid(NULL, &ctx, nid, value);
    if (!ex)
        return 0;

    X509_add_ext(cert,ex,-1);
    X509_EXTENSION_free(ex);
    return 1;
    }



int add_ext(X509 *cert, int nid, char *value);

int mkcert(X509 **x509p, EVP_PKEY **pkeyp, int bits, int serial, int days);




MODULE = GenerateSSLCerts        PACKAGE = GenerateSSLCerts

int
gen_key_n_cert(char *key_file, char *cert_file, int bits, int serial, int days)
    PREINIT:
        BIO *bio_err;
        X509 *x509=NULL;
        EVP_PKEY *pkey=NULL;
        FILE *fp;
    CODE:
        CRYPTO_mem_ctrl(CRYPTO_MEM_CHECK_ON);

        bio_err=BIO_new_fp(stderr, BIO_NOCLOSE);

        mkcert(&x509, &pkey, bits, serial, days);

        if (!(fp = fopen(key_file, "w")))
            fatal("Error opening key file for writing");

        if ( PEM_write_PrivateKey(fp, pkey, NULL, NULL, 0, NULL, NULL) != 1 )
            fatal("Error while writing to key file");
        fclose(fp);

        if (!(fp = fopen(cert_file, "w")))
            fatal("Error opening certificate file for writing");

        if ( PEM_write_X509(fp, x509) != 1 )
            fatal("Error while writing to certificate file");
        fclose(fp);

        X509_free(x509);
        EVP_PKEY_free(pkey);

        ENGINE_cleanup();

        CRYPTO_cleanup_all_ex_data();

        CRYPTO_mem_leaks(bio_err);
        BIO_free(bio_err);
        RETVAL=0;
    OUTPUT:
        RETVAL
