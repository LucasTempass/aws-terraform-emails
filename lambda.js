// TODO implementar disparo para o SQS

module.exports.handler = async (event) => {
    console.log('Event: ', event);

    const responseMessage = 'Hello, World!';

    const headers = {
        'Content-Type': 'application/json',
    };

    return {
        statusCode: 200,
        headers: headers,
        body: JSON.stringify({
            message: responseMessage,
        }),
    }
}