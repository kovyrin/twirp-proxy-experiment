vcl 4.1;

# We need these to be able to cache POST requests
import std;
import bodyaccess;

# Point this at the API server
backend default {
    .host = "127.0.0.1";
    .port = "3001";
}

sub vcl_recv {
    set req.http.x-method = req.method;
    unset req.http.x-attempt-to-cache-post;

    # Check for no-cache directives in client request and force a miss for those
    if (req.http.Cache-Control ~ "no-cache" || req.http.Cache-Control ~ "max-age=0") {
        set req.hash_always_miss = true;
    }

    # Check for no-store directives in client request and pass those through
    if (req.http.Cache-Control ~ "no-store") {
        return(pass);
    }

    # Allow POST requests to be cached
    if (req.method == "POST") {
        std.log("Attempting to cache a POST request: " + req.url);
        set req.http.x-attempt-to-cache-post = "1";
        if (std.cache_req_body(500KB)) {
            return(hash);
        }
    }
}

sub vcl_hash {
    if (req.http.x-attempt-to-cache-post) {
        std.log("Hashing a POST body");
        bodyaccess.hash_req_body();
    }
}

sub vcl_backend_fetch {
    # Set the method to the original value to make sure we pass POST requests to the backend
    set bereq.method = bereq.http.x-method;
}
