
#include <stdio.h>
#include <string.h>
#include "nanohttpd.h"

int http_req_parse( http_req_t * );
void http_req_free( void * );

const hash_t *http_req_get_headers( http_req_t * );
const list_t *http_req_get_header( http_req_t *, const char * );
const list_t *http_req_get_cookies( http_req_t * );
char *http_req_get_cookie( http_req_t *, const char * );
list_t *http_req_get_parameters( http_req_t * );
const char *http_req_get_parameter( http_req_t *, const char * );

http_req_t *http_req_new( int sock ) {
	http_req_t *me = (http_req_t *) malloc( sizeof( http_req_t ) );
	me -> sock = sock;
	me -> netbuf = netbuf_in_new( sock );

	me -> query = NULL;
	me -> file_name = NULL;
	me -> headers = hash_new();

	me -> content = NULL;
	me -> parameters = NULL;
	me -> mime_msg = NULL;

	me -> get_headers = http_req_get_headers;
	me -> get_header = http_req_get_header;
	me -> get_cookies = http_req_get_cookies;
	me -> get_cookie = http_req_get_cookie;
	me -> get_parameters = http_req_get_parameters;
	me -> get_parameter = http_req_get_parameter;
	me -> delete = http_req_free;

	return me;
}

const hash_t *http_req_get_headers( http_req_t *me ) {
	return me -> headers;
}

const list_t *http_req_get_header( http_req_t *me, const char *header ) {
	return me -> headers -> get( me -> headers, header );
}

const list_t *http_req_get_cookies( http_req_t *me ) {
	return me -> get_header( me, "cookie" );
}

char *http_req_get_cookie( http_req_t *me, const char *name ) {
	list_t *cookies = (list_t *) me -> get_cookies( me );
	if( ! cookies ) return NULL;

	char *cookie = (char *) cookies -> first( cookies );
	while( cookie ) {
		char *buf = strdup( cookie );
		char *tmp = buf;
		while( buf ) {
			char *key = strsep( &buf, "=;" );
			if( *key != '\0' ) {
				char *value = strsep( &buf, ";" );
				while( *key == ' ' ) key++;
				if( ! strcmp( name, key ) ) {
					free( tmp );
					return ( value ? strdup( value ) : NULL );
				}
			}
		}

		free( tmp );
		cookie = (char *) cookies -> next( cookies );
	}

	return NULL;
}

list_t *http_req_get_parameters( http_req_t *me ) {
	if( ! me -> parameters ) return NULL;
	return me -> parameters -> keys( me -> parameters );
}

const char *http_req_get_parameter( http_req_t *me, const char *param ) {
	if( ! me -> parameters ) return NULL;
	return me -> parameters -> get( me -> parameters, param );
}

static int http_req_add_header( http_req_t *me, const char *header, char *value ) {
	char *head = strdup( header );
	strtolower( head );

	list_t *h = (list_t *) me -> headers -> get( me -> headers, head );
	if( h ) h -> add( h, value );
	else {
		h = list_new();
		h -> add( h, value );
		me -> headers -> set( me -> headers, (char *) head, h );
	}

	return 0;
}

static hash_t *http_req_parse_parameters( http_req_t *me ) {
	if( ! me -> query || ! strlen( me -> query ) )
		return NULL;

	hash_t *ret = hash_new();
	char *buf = strdup( me -> query );
	char *tmp = buf;
	while( buf ) {
		char *param = strsep( &buf, "=&" );
		if( *param != '\0' ) {
			url_decode( param, 1 );
			char *value = strsep( &buf, "&" );
			if( value ) {
				url_decode( value, 1 );
				ret -> set( ret, strdup( param ), strdup( value ) );
			} else ret -> set( ret, strdup( param ), NULL );
		}
	}

	free( tmp );
	return ret;
}

int http_req_parse( http_req_t *me ) {
	char *line = (char *) malloc( 255 );
	if( me -> netbuf -> read_line( me -> netbuf, line, 255 ) < 0 ) {
		free( line );
		return REQ_BAD_REQUEST;
	}

#ifdef LOG_HTTP
	http_log( LOG_DEBUG, "request: %s", line );
#endif

	char *org = line;
	char *uri = NULL;
	char *version = NULL;
	char *method = strsep( &line, " \r\n" );
	if( line ) {
		uri = strsep( &line, " \r\n" );
		if( uri ) version = strsep( &line, " \r\n" );
	} else {
		free( org );
		return REQ_BAD_REQUEST;
	}

	if( ! uri  || ! method ) {
		free( org );
		return REQ_BAD_REQUEST;
	}

	me -> uri = strdup( uri );
	me -> query = strdup( uri );
	me -> file_name = strsep( &(me -> query), "?" );
	url_decode( me -> file_name, 0 );

	me -> method = 0;
	if( ! strncasecmp( "POST", method, 4 ) )
		me -> method = REQ_POST;
	if( ! strncasecmp( "GET", method, 3 ) )
		me -> method = REQ_GET;

	me -> version = REQ_HTTP09;

	if( version ) {
		if( strstr( version, "HTTP/1.1" ) )
			me -> version = REQ_HTTP11;
		else if( strstr( version, "HTTP/1.0" ) )
			me -> version = REQ_HTTP10;
	}

	line = org;
	if( me -> version != REQ_HTTP09 ) {
		do {
			me -> netbuf -> read_line( me -> netbuf, line, 255 );

			char *buf = strdup( line );
			char *orgbuf = buf;

			char *field_name = strsep( &buf, ":\r\n" );
			if( buf ) {
				char *field_value = strsep( &buf, "\r\n" );
				while( *field_value == ' ' ) field_value++;
				if( buf ) http_req_add_header( me, field_name, strdup( field_value ) );
			}

			free( orgbuf );			
		} while( strlen( line ) > 2 );
	}

	free( org );

	if( me -> headers -> get( me -> headers, "content-type" ) ) {
		list_t *list = (list_t *) me -> headers -> get( me -> headers, "content-length" );

		if( list ) {
			unsigned long buflen = atol( (char *) list -> first( list ) );
			me -> content_length = buflen;

#ifdef LOG_HTTP
			http_log( LOG_DEBUG, "Reading %lu(%s) bytes", buflen, (char *) list -> first( list ) );
#endif

			if( buflen > 0 ) {
				me -> content = (char *) malloc( buflen );

				unsigned long nread = 0;
				while( nread < buflen )
					nread += me -> netbuf -> read( me -> netbuf, me -> content + nread, buflen - nread );

				list = (list_t *) me -> headers -> get( me -> headers, "content-type" );
				char *buf = (char *) list -> first( list );

				char *boundary = strstr( buf, "boundary=" );
				if( boundary ) {
					boundary += strlen( "boundary=" );
					if( *boundary == '"' ) {
						// remove the leading & trailing " if any
						boundary++;
						boundary = strsep( &boundary, "\"" );
					}

					me -> mime_msg = mime_parse_message( me -> content, &buflen, boundary);
				}
#ifdef LOG_HTTP
				else http_log( LOG_ERR, "Boundary parameter not found in Content-Type!" );
#endif
			}
		}
	}

	me -> parameters = http_req_parse_parameters( me );

	return 0;
}

#define free_if_not_null(x) if(x !=NULL) free(x)

void http_req_free( void *_me ) {
	http_req_t *me = (http_req_t *) _me;

	free_if_not_null( me -> uri );
	free_if_not_null( me -> file_name );
	free_if_not_null( me -> content );

	if( me -> headers )
		me -> headers -> delete( me -> headers, 1, 1, list_free );

	if( me -> netbuf )
		me -> netbuf -> delete( me -> netbuf );

	if( me -> parameters )
		me -> parameters -> delete( me -> parameters, 1, 1, NULL );

	if( me -> mime_msg )
		me -> mime_msg -> delete( me -> mime_msg );

	free( me );
}
