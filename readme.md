# Delorme-2-Social

Delomre-2-Tumblr is a ruby script that grabs the Delorme MapShare KML and creates a Tumblr post.

In particular, it does the following
* Pulls the Delorme MapShare KML feed
* Extracts the points from the KML
* Creates a static map image based on the points from the KML
* Gets the current weather conditions and upcoming forecast based upon the last point
* Posts a blog entry on Tumblr
* Posts a blog entry on Twitter
* Uploads the static map image to AWS S3
* Sends a Twilio SMS/MMS message with the static map image.

## Setting up the script

The following items have to be setup in the `config.yml` file. Copy the `config.template` and set appropriately.

## Configuration

Google Maps
```
GOOGLE_MAPS_API_KEY: "---"
```

Tumblr API
```
TUMBLR_CONSUMER_KEY: "---"
TUMBLR_CONSUMER_SECRET: "---"
TUMBLR_OAUTH_TOKEN: "---"
TUMBLR_OAUTH_TOKEN_SECRET: "---"
```

Tumbr Blog
```
TUMBLR_ACCOUNT: "---"
TUMBLR_HIKER_NAME: "---"
TUMBLR_BLOG_URL: "---"
```

Delorme MapShare KML Feed
```
DELORME_INREACH_MAPSHARE: "---"
DELORME_INREACH_MAPSHARE_ACCOUNT: "---"
DELORME_INREACH_MAPSHARE_PASSWORD: "---"
```

Forecast IO API
```
FORECAST_IO_API_KEY: "---"
```

AWS S3 API - support MMS images for Twilio
```
AWS_S3_ACCESS_KEY: "---"
AWS_S3_SECRET_KEY: "---"
AWS_S3_BUCKET: "---"
AWS_S3_FOLDER: "---"
```

Twilio MMS API
```
TWILIO_NUMBER: '---' 
TWILIO_ACCOUNT_SID: '---' 
TWILIO_AUTH_TOKEN: '---' 
```

Twilio SMS/MMS Recipient list
```
SMS_RECIPIENTS: '{ "+12025551212": "John",  "+12025551212": "Jane" }'
```





