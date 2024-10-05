const AWS = require('aws-sdk');

const ses = new AWS.SES({ region: 'sa-east-1' });

exports.handler = async (event) => {
    const params = {
        Source: '', // replace with your verified email address
        Destination: {
            ToAddresses: [] // replace with the recipient's email address
        },
        Message: {
            Subject: {
                Data: 'Test email from Lambda' // replace with your email subject
            },
            Body: {
                Text: {
                    Data: 'This is a test email sent from a Lambda function.' // replace with your email body
                }
            }
        }
    };

    try {
        const result = await ses.sendEmail(params).promise();
        console.log(result);
        return result;
    } catch (err) {
        console.log(err);
        throw err;
    }
};