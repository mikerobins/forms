'use strict';

var doc = require('dynamodb-doc');
var db = new doc.DynamoDB();

console.log('Loading function');

exports.handler = (event, context, callback) => {
    //console.log('Received event:', JSON.stringify(event, null, 2));
    event.Records.forEach((record) => {
        // Kinesis data is base64 encoded so decode here
        const payload = new Buffer(record.kinesis.data, 'base64').toString('utf-8');
        console.log('Decoded payload:', payload);
        
        console.log("Parsing data");
        const blob = JSON.parse(payload);
        console.log("Parsed data");
    
        if(blob.hasOwnProperty('created_at')) {
            
            console.log("Got a Tweet");
    
            var tableName = process.env.TABLE_NAME;
            var item = {
                "tweet_id" :String(blob.id),
	        "tweet" : payload,
                "tweet_text" : blob.text
            };
 
            var params = {
                TableName:tableName, 
                Item: item
            };
            
            console.log(params);
            
            db.putItem(params,function(err,data) {
                if (err) {
                    console.log(err);
                } else {
                    console.log(data);
                }
            });
        }
    });
    callback(null, `Successfully processed ${event.Records.length} records.`);
};

