from __future__ import print_function

import base64
import boto3
import json

print('Loading function')

dynamodb = boto3.resource('dynamodb')
comprehend = boto3.client(service_name='comprehend', region_name='us-east-1')
table = dynamodb.Table('twitter_sentiment')

def handler(event, context):
    #print("Received event: " + json.dumps(event, indent=2))
    for record in event['Records']:
        # Kinesis data is base64 encoded so decode here and process
        payload = base64.b64decode(record['kinesis']['data'])
        tweet = json.loads(payload)
        
        if 'created_at' in tweet:
            tweet_text = tweet['text']
            rawlang = comprehend.detect_dominant_language(Text=tweet_text)
            lang = json.dumps(rawlang)
            print("lang is " + lang)
            sentiment = "not supported"
        
            firstlang = rawlang["Languages"][0]["LanguageCode"]
        
            if firstlang == 'en':
                print("Got en")
                sentiment = json.dumps(comprehend.detect_sentiment(Text=tweet_text, LanguageCode='en'))
        
            table.put_item(
                Item={
                    'tweet_id': json.dumps(tweet['id']),
                    'language': json.dumps(lang),
                    'sentiment' : sentiment
                }
            )
  #      
    return 'Successfully processed {} records.'.format(len(event['Records']))

