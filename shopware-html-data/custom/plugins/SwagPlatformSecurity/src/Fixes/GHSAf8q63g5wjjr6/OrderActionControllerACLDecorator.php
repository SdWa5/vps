<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAf8q63g5wjjr6;

use Shopware\Core\Checkout\Order\Api\OrderActionController;
use Shopware\Core\Framework\Context;
use Shopware\Core\System\StateMachine\StateMachineException;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;

class OrderActionControllerACLDecorator extends OrderActionController
{
    public function __construct(
        private readonly OrderActionController $decorated
    ) {
    }

    public function orderStateTransition(string $orderId, string $transition, Request $request, Context $context): JsonResponse
    {
        if (!$context->isAllowed('order:update')) {
            throw StateMachineException::missingPrivileges(['order:update']);
        }

        return $this->decorated->orderStateTransition($orderId, $transition, $request, $context);
    }

    public function orderTransactionStateTransition(string $orderTransactionId, string $transition, Request $request, Context $context): JsonResponse
    {
        if (!$context->isAllowed('order_transaction:update')) {
            throw StateMachineException::missingPrivileges(['order_transaction:update']);
        }

        return $this->decorated->orderTransactionStateTransition($orderTransactionId, $transition, $request, $context);
    }

    public function orderDeliveryStateTransition(string $orderDeliveryId, string $transition, Request $request, Context $context): JsonResponse
    {
        if (!$context->isAllowed('order_delivery:update')) {
            throw StateMachineException::missingPrivileges(['order_delivery:update']);
        }

        return $this->decorated->orderDeliveryStateTransition($orderDeliveryId, $transition, $request, $context);
    }

    public function refundOrderTransactionCapture(string $refundId, Context $context): JsonResponse
    {
        return $this->decorated->refundOrderTransactionCapture($refundId, $context);
    }
}
