<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAr2vghvjmfg38;

use Shopware\Core\Framework\ShopwareHttpException;
use Symfony\Component\HttpFoundation\Response;

class OrderNotCancellableException extends ShopwareHttpException
{
    public function __construct()
    {
        parent::__construct('Order cannot be cancelled.');
    }

    public function getErrorCode(): string
    {
        return 'CHECKOUT__ORDER_NOT_CANCELLABLE';
    }

    public function getStatusCode(): int
    {
        return Response::HTTP_FORBIDDEN;
    }
}
